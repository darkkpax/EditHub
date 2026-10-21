use crate::projects::{self, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};

// OAuth desktop client IDs are intentionally public. PKCE protects the login
// flow, so a client secret must never be bundled with this distributable app.
const BUNDLED_GOOGLE_CLIENT_ID: &str = "875188896849-71kig4s8vrn00c3aivj9hum9h1at8n0q.apps.googleusercontent.com";
fn normalize_credentials(mut c: Value) -> Result<Value> {
    if !c.is_object() {
        return Err("Invalid google-drive.json: expected a credentials object".into());
    }
    for (canonical, alias) in [
        ("apiKey", "api_key"),
        ("clientId", "client_id"),
        ("clientSecret", "client_secret"),
        ("access_token", "accessToken"),
        ("refresh_token", "refreshToken"),
    ] {
        if !c[canonical].as_str().is_some_and(|v| !v.trim().is_empty()) {
            if let Some(value) = c[alias]
                .as_str()
                .filter(|v| !v.trim().is_empty())
                .map(str::to_owned)
            {
                c[canonical] = json!(value);
            }
        }
    }
    Ok(c)
}
fn read_credentials(path: &std::path::Path) -> Result<Value> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("Could not read google-drive.json: {e}"))?;
    let value = serde_json::from_str(text.trim_start_matches('\u{feff}'))
        .map_err(|_| "Invalid JSON in google-drive.json")?;
    normalize_credentials(value)
}
fn merge_token_response(credentials: Value, token: Value, now: i64) -> Result<Value> {
    let mut credentials = normalize_credentials(credentials)?;
    if !token["access_token"]
        .as_str()
        .is_some_and(|v| !v.is_empty())
    {
        return Err("Google access token missing".into());
    }
    credentials["expiresAt"] = json!(now + token["expires_in"].as_i64().unwrap_or(3600) * 1000);
    let mut fields = token.as_object().ok_or("Invalid Google response")?.clone();
    if !fields
        .get("refresh_token")
        .and_then(Value::as_str)
        .is_some_and(|v| !v.is_empty())
    {
        fields.remove("refresh_token");
    }
    credentials.as_object_mut().unwrap().extend(fields);
    if let Some(refresh) = credentials["refresh_token"].as_str().map(str::to_owned) {
        credentials["refreshToken"] = json!(refresh);
    }
    Ok(credentials)
}
fn credentials() -> Result<Value> {
    let path = projects::config_dir().join("google-drive.json");
    if path.exists() {
        read_credentials(&path)
    } else {
        Ok(json!({ "clientId": BUNDLED_GOOGLE_CLIENT_ID }))
    }
}
static REFRESH_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
pub async fn access(c: &reqwest::Client) -> Result<(Option<String>, Option<String>)> {
    let _guard = REFRESH_LOCK.lock().await;
    let credentials = credentials()?;
    let key = credentials["apiKey"]
        .as_str()
        .filter(|v| !v.is_empty())
        .map(str::to_owned);
    let now = chrono::Utc::now().timestamp_millis();
    if credentials["expiresAt"].as_f64().unwrap_or(0.0) > (now + 60000) as f64 {
        if let Some(token) = credentials["access_token"]
            .as_str()
            .filter(|v| !v.is_empty())
        {
            return Ok((Some(token.into()), key));
        }
    }
    let Some(refresh) = credentials["refresh_token"]
        .as_str()
        .filter(|v| !v.is_empty())
    else {
        return Ok((None, key));
    };
    let client = credentials["clientId"]
        .as_str()
        .filter(|v| !v.is_empty())
        .ok_or("Google session exists, but clientId is missing")?;
    let mut form = vec![
        ("client_id", client),
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh),
    ];
    if let Some(secret) = credentials["clientSecret"]
        .as_str()
        .filter(|v| !v.is_empty())
    {
        form.push(("client_secret", secret));
    }
    let response = c
        .post("https://oauth2.googleapis.com/token")
        .form(&form)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|_| {
            "Could not reach Google to refresh access. Credentials preserved; check connection"
        })?;
    if !response.status().is_success() {
        return Err(format!("Google rejected session refresh (HTTP {}). Credentials preserved; reconnect in Settings",response.status().as_u16()));
    }
    let token: Value = response
        .json()
        .await
        .map_err(|_| "Invalid Google refresh response")?;
    let updated = merge_token_response(credentials, token, now)?;
    let access = updated["access_token"].as_str().unwrap().to_string();
    projects::write_json(&projects::config_dir().join("google-drive.json"), &updated)?;
    Ok((Some(access), key))
}
#[tauri::command]
pub async fn google_status() -> Result<Value> {
    let c = credentials()?;
    let has_session = c["refresh_token"].as_str().is_some_and(|v| !v.is_empty())
        || c["access_token"].as_str().is_some_and(|v| !v.is_empty());
    let mut connected = false;
    if has_session {
        let client = reqwest::Client::new();
        if let Some(token) = access(&client).await?.0 {
            let response = client
                .get("https://www.googleapis.com/drive/v3/about")
                .query(&[("fields", "user(permissionId)")])
                .bearer_auth(token)
                .timeout(Duration::from_secs(20))
                .send()
                .await
                .map_err(|_| "Could not verify Google Drive connection. Credentials preserved")?;
            if !response.status().is_success() {
                return Err(format!(
                    "Could not verify Google Drive access (HTTP {}). Credentials preserved",
                    response.status().as_u16()
                ));
            }
            connected = true;
        }
    }
    Ok(
        json!({"configured":c["clientId"].as_str().is_some_and(|s|!s.is_empty()),"connected":connected,"hasApiKey":c["apiKey"].as_str().is_some_and(|s|!s.is_empty())}),
    )
}
#[tauri::command]
pub async fn configure_google(
    client_id: String,
    client_secret: String,
    api_key: String,
) -> Result<()> {
    let _guard = REFRESH_LOCK.lock().await;
    let mut c = credentials()?;
    for (key, value) in [
        ("clientId", client_id),
        ("clientSecret", client_secret),
        ("apiKey", api_key),
    ] {
        if !value.trim().is_empty() {
            c[key] = json!(value.trim());
        }
    }
    projects::write_json(&projects::config_dir().join("google-drive.json"), &c)
}
#[tauri::command]
pub async fn connect_google() -> Result<()> {
    let mut c = credentials()?;
    let client = c["clientId"]
        .as_str()
        .ok_or("Set a Desktop app OAuth client ID first")?
        .to_string();
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| e.to_string())?;
    let redirect = format!(
        "http://127.0.0.1:{}/oauth2callback",
        listener.local_addr().map_err(|e| e.to_string())?.port()
    );
    let verifier = format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    );
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let state = uuid::Uuid::new_v4().to_string();
    let mut url = url::Url::parse("https://accounts.google.com/o/oauth2/v2/auth").unwrap();
    url.query_pairs_mut().extend_pairs([
        ("client_id", client.as_str()),
        ("redirect_uri", &redirect),
        ("response_type", "code"),
        ("scope", "https://www.googleapis.com/auth/drive.readonly"),
        ("access_type", "offline"),
        ("prompt", "consent"),
        ("code_challenge", &challenge),
        ("code_challenge_method", "S256"),
        ("state", &state),
    ]);
    open::that_detached(url.as_str()).map_err(|e| e.to_string())?;
    let code=tokio::time::timeout(Duration::from_secs(180),async {
        loop {
            let (mut socket,_)=listener.accept().await.map_err(|e|e.to_string())?;let mut data=vec![0u8;16384];
            let size=tokio::time::timeout(Duration::from_secs(5),socket.read(&mut data)).await.map_err(|_|"Browser callback timed out")?.map_err(|e|e.to_string())?;
            let request=String::from_utf8_lossy(&data[..size]);
            let path=request.lines().next().and_then(|v|v.split_whitespace().nth(1)).unwrap_or("");
            let parsed=url::Url::parse(&format!("http://127.0.0.1{path}")).map_err(|e|e.to_string())?;
            let valid=parsed.path()=="/oauth2callback" && parsed.query_pairs().any(|(k,v)|k=="state" && v==state);
            let code=parsed.query_pairs().find(|(k,_)|k=="code").map(|(_,v)|v.into_owned());
            let ok=valid && code.is_some();
            let body=if ok{"Connected. You can close this tab."}else{"Invalid or cancelled authorization."};
            socket.write_all(format!("HTTP/1.1 {}\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",if ok{"200 OK"}else{"400 Bad Request"},body.len()).as_bytes()).await.map_err(|e|e.to_string())?;
            if valid {return code.ok_or_else(||"Google sign-in cancelled".to_string());}
        }
    }).await.map_err(|_|"Google sign-in timed out")??;
    let _guard = REFRESH_LOCK.lock().await;
    c = credentials()?;
    if c["clientId"].as_str() != Some(client.as_str()) {
        return Err(
            "Google settings changed during sign-in. Try again; current credentials preserved"
                .into(),
        );
    }
    let mut form = vec![
        ("client_id", client.as_str()),
        ("code", code.as_str()),
        ("code_verifier", verifier.as_str()),
        ("redirect_uri", redirect.as_str()),
        ("grant_type", "authorization_code"),
    ];
    if let Some(secret) = c["clientSecret"].as_str().filter(|v| !v.is_empty()) {
        form.push(("client_secret", secret));
    }
    let response = reqwest::Client::new()
        .post("https://oauth2.googleapis.com/token")
        .form(&form)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err("Google rejected sign-in. Check OAuth client ID and Desktop app type".into());
    }
    let token: Value = response.json().await.map_err(|e| e.to_string())?;
    c = merge_token_response(c, token, chrono::Utc::now().timestamp_millis())?;
    projects::write_json(&projects::config_dir().join("google-drive.json"), &c)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    #[ignore = "uses existing local credentials and Google API"]
    async fn existing_google_credentials_work() {
        let loaded = credentials().expect("existing credentials could not be read");
        for field in ["apiKey", "clientId", "clientSecret", "refresh_token"] {
            assert!(
                loaded[field].as_str().is_some_and(|v| !v.is_empty()),
                "missing existing credential field: {field}"
            );
        }
        let status = google_status()
            .await
            .expect("existing session verification failed");
        assert_eq!(status["connected"], true);
        let client = reqwest::Client::new();
        let (token, key) = access(&client).await.expect("token refresh failed");
        let source = std::env::var("EDITHUB_LIVE_DRIVE_URL")
            .expect("set EDITHUB_LIVE_DRIVE_URL to the test folder");
        let folder = url::Url::parse(&source).expect("invalid test folder URL");
        assert_eq!(folder.host_str(), Some("drive.google.com"));
        let id = folder
            .path_segments()
            .and_then(|parts| parts.filter(|p| !p.is_empty()).next_back())
            .expect("no test folder ID");
        assert!(id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-'));
        let response = client
            .get(format!("https://www.googleapis.com/drive/v3/files/{id}"))
            .query(&[
                ("fields", "mimeType"),
                ("key", key.as_deref().expect("existing API key missing")),
            ])
            .bearer_auth(token.expect("access token missing"))
            .timeout(Duration::from_secs(30))
            .send()
            .await
            .unwrap_or_else(|_| {
                panic!("Drive API request failed; sensitive request details omitted")
            });
        assert_eq!(response.status().as_u16(), 200);
        let data: Value = response.json().await.expect("invalid Drive API response");
        assert_eq!(data["mimeType"], "application/vnd.google-apps.folder");
        println!("existing keys loaded; saved session verified; Drive folder API: HTTP 200");
    }
    #[test]
    fn loads_existing_bom_json_and_legacy_names() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("google-drive.json");
        std::fs::write(&path,concat!("\u{feff}",r#"{"api_key":"existing-key","client_id":"existing-client","client_secret":"existing-secret","refresh_token":"","refreshToken":"existing-refresh","accessToken":"existing-access"}"#)).unwrap();
        let c = read_credentials(&path).unwrap();
        assert_eq!(c["apiKey"], "existing-key");
        assert_eq!(c["clientId"], "existing-client");
        assert_eq!(c["clientSecret"], "existing-secret");
        assert_eq!(c["refresh_token"], "existing-refresh");
        assert_eq!(c["access_token"], "existing-access");
    }
    #[test]
    fn refresh_keeps_existing_keys_and_refresh_token() {
        let c=merge_token_response(json!({"apiKey":"key","clientId":"client","clientSecret":"secret","refreshToken":"refresh","unknownField":17}),json!({"access_token":"new-access","expires_in":3600}),1000).unwrap();
        assert_eq!(c["refresh_token"], "refresh");
        assert_eq!(c["apiKey"], "key");
        assert_eq!(c["unknownField"], 17);
        assert_eq!(c["expiresAt"], 3601000);
    }
    #[test]
    fn malformed_credentials_are_reported() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("google-drive.json");
        std::fs::write(&path, "[]").unwrap();
        assert!(read_credentials(&path).is_err());
    }
}
