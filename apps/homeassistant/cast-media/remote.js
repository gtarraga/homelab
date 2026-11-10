"use strict";
/**
 * Home Assistant / Fire TV remote control.
 * Pure device layer — no Raycast dependency.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.wakeProjector = wakeProjector;
exports.wakeFireTV = wakeFireTV;
exports.sendIntent = sendIntent;
exports.wakeAndLaunch = wakeAndLaunch;
const dgram_1 = require("dgram");
const node_crypto_1 = require("node:crypto");
async function haFetch(config, path, init) {
    const base = config.haUrl.replace(/\/+$/, "");
    const res = await fetch(`${base}${path}`, {
        ...init,
        signal: AbortSignal.timeout(15_000),
        headers: {
            Authorization: `Bearer ${config.haToken}`,
            "Content-Type": "application/json",
            ...(init?.headers || {}),
        },
    });
    if (!res.ok) {
        // Response bodies can contain private infrastructure details.
        throw new Error(`Home Assistant request failed (HTTP ${res.status})`);
    }
    return res;
}
async function callService(config, domain, service, data) {
    return haFetch(config, `/api/services/${domain}/${service}`, {
        method: "POST",
        body: JSON.stringify(data),
    });
}
async function getEntity(config, entityId) {
    const res = await haFetch(config, `/api/states/${entityId}`);
    return (await res.json());
}
async function isOff(config, entityId) {
    try {
        const { state } = await getEntity(config, entityId);
        return state === "off" || state === "standby" || state === "unavailable";
    }
    catch {
        return true;
    }
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
/** HA can accept a command without the device executing it. Require fresh shell output. */
async function runAdb(config, command) {
    const marker = `CAST_${(0, node_crypto_1.randomUUID)().replace(/-/g, "")}`;
    await callService(config, "androidtv", "adb_command", {
        entity_id: config.entityId,
        command: `{ ${command}; }; cast_exit=$?; printf '\\n${marker}:%s\\n' "$cast_exit"`,
    });
    // HA's androidtv integration publishes shell output in this entity attribute.
    // A per-command marker prevents a previous successful response being reused.
    const entity = await getEntity(config, config.entityId);
    const response = entity.attributes?.adb_response;
    if (typeof response !== "string")
        throw new Error("No confirmed ADB response from Fire TV");
    const match = response.match(new RegExp(`\\n?${marker}:(\\d+)\\s*$`));
    if (!match || match.index === undefined)
        throw new Error("No confirmed ADB response from Fire TV");
    return { output: response.slice(0, match.index), exitCode: Number(match[1]) };
}
/** Probe Android itself, even if HA has a cached 'on' state or the projector was already on. */
async function waitForAndroidReady(config, onProgress) {
    const deadline = Date.now() + 90_000;
    while (Date.now() < deadline) {
        try {
            const result = await runAdb(config, 'test "$(getprop sys.boot_completed)" = 1 && pm path android >/dev/null');
            if (result.exitCode === 0)
                return;
        }
        catch {
            // ADB may disconnect during boot; never treat an old HA state as readiness.
        }
        onProgress?.("Waiting for Fire TV's Android system to finish booting…");
        await sleep(3000);
    }
    throw new Error("Fire TV's Android system was not ready after 90s; check its ADB connection");
}
function parseMac(mac) {
    const hex = mac.replace(/[^0-9a-fA-F]/g, "");
    if (hex.length !== 12)
        throw new Error(`Invalid MAC: ${mac}`);
    return Buffer.from(hex, "hex");
}
function sendWol(mac) {
    return new Promise((resolve, reject) => {
        const macBuf = parseMac(mac);
        const packet = Buffer.alloc(6 + 16 * 6);
        packet.fill(0xff, 0, 6);
        for (let i = 0; i < 16; i++)
            macBuf.copy(packet, 6 + i * 6);
        const socket = (0, dgram_1.createSocket)("udp4");
        let done = false;
        const finish = (err) => {
            if (done)
                return;
            done = true;
            socket.close();
            if (err)
                reject(err);
            else
                resolve();
        };
        socket.on("error", (err) => finish(err));
        socket.bind(0, () => {
            socket.setBroadcast(true);
            socket.send(packet, 9, "255.255.255.255", (err) => finish(err));
        });
    });
}
async function wakeProjector(config, onProgress) {
    if (!config.projectorEntityId || !config.projectorMac)
        return false;
    const off = await isOff(config, config.projectorEntityId);
    if (!off)
        return false;
    onProgress?.("Turning On Projector…");
    await sendWol(config.projectorMac);
    await new Promise((r) => setTimeout(r, 5000));
    return true;
}
async function wakeFireTV(config, _projectorWasOff, onProgress) {
    await waitForAndroidReady(config, onProgress);
    onProgress?.("Waking Fire TV…");
    // POWER (26) toggles and can put an auto-booted device straight back to sleep.
    const result = await runAdb(config, "input keyevent KEYCODE_WAKEUP");
    if (result.exitCode !== 0)
        throw new Error("Fire TV wake command failed");
    await sleep(500);
}
async function sendIntent(config, intent, onProgress) {
    const packageName = intent.match(/\s-n\s+([\w.]+)\//)?.[1] ?? intent.match(/\s([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)+)\s*$/)?.[1];
    if (!/^am start\b/.test(intent) || !packageName)
        throw new Error("Cannot verify the target app for this launch command");
    const command = /\s-W(?:\s|$)/.test(intent) ? intent : intent.replace(/^am start\b/, "am start -W");
    const result = await runAdb(config, command);
    if (result.exitCode !== 0 ||
        /(?:^|\n)\s*(?:Error\b|Exception\b)|\b(?:SecurityException|ActivityNotFoundException|AndroidRuntimeException)\b|unable to resolve Intent|does not exist|Status:\s*timeout/i.test(result.output)) {
        throw new Error("Android could not launch the requested app; check that it is installed and supports this link");
    }
    onProgress?.("Verifying the app is open on Fire TV…");
    const deadline = Date.now() + 15_000;
    const escapedPackage = packageName.replace(/\./g, "\\.");
    const foreground = new RegExp(`(?:mResumedActivity|topResumedActivity|mFocusedActivity)\\s*[:=]\\s*[^\\n]*[\\s{]${escapedPackage}/`);
    while (Date.now() < deadline) {
        try {
            const activity = await runAdb(config, "dumpsys activity activities");
            if (activity.exitCode === 0 && foreground.test(activity.output))
                return;
        }
        catch {
            // Retry a transient ADB disconnect, but never report an unverified launch.
        }
        await sleep(1000);
    }
    throw new Error("The requested app did not reach the foreground; Fire TV may still be at its menu");
}
async function wakeAndLaunch(config, intent, onProgress) {
    const projectorWasOff = await wakeProjector(config, onProgress);
    await wakeFireTV(config, projectorWasOff, onProgress);
    await sendIntent(config, intent, onProgress);
}
