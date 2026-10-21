//! Security smoke test compiled against the server exact locked reqwest/rustls dependencies.
#[tokio::main]
async fn main() {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build().expect("build standard certificate-validating client");
    for host in [
        "ov-g3c-aaa-emudhra.we-have-a-problem.com",
        "ev-g3c-emudhra.we-have-a-problem.com",
        "ov-g3b-aaa-emudhra.we-have-a-problem.com",
        "ov-g3b-emudhra.we-have-a-problem.com",
        "ev-g3b-aaa-emudhra.we-have-a-problem.com",
        "ev-g3c-aaa-emudhra.we-have-a-problem.com",
        "ev-g3b-emudhra.we-have-a-problem.com",
        "ov-g3c-emudhra.we-have-a-problem.com",
        "dv-g3b-aaa-emudhra.we-have-a-problem.com",
        "dv-g3c-aaa-emudhra.we-have-a-problem.com",
        "dv-g3b-emudhra.we-have-a-problem.com",
        "dv-g3c-emudhra.we-have-a-problem.com"
    ] {
        let result = client.get(format!("https://{host}/")).send().await;
        let error = result.expect_err("compromised chain must be rejected");
        let detail = format!("{error:?}");
        assert!(detail.to_lowercase().contains("certificate"), "must reject certificate, not fail networking: {detail}");
        println!("{host}: CERTIFICATE_REJECTED {detail}");
    }
    let response = client.get("https://www.google.com/").send().await
        .expect("ordinary public HTTPS must remain trusted");
    println!("www.google.com: ACCEPTED {}", response.status());
}
