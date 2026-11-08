use crate::projects::{self, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::TcpListener,
    sync::Mutex,
};
use url::Url;

const REDIRECT: &str = "http://127.0.0.1:53682/oauth2callback";
const SCOPE: &str = "sharing.read files.metadata.read";
static SIGN_IN: Mutex<()> = Mutex::const_new(());
static ACCESS: Mutex<Option<Access>> = Mutex::const_new(None);

#[derive(Serialize, Deserialize)]
struct Session {
    app_key: String,
    refresh_token: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
    refresh_token: Option<String>,
}

struct Access {
    token: String,
    expires: Instant,
}

fn session_path() -> PathBuf {
    projects::config_dir().join("dropbox-session.json")
}

fn session() -> Result<Option<Session>> {
    match std::fs::read(session_path()) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|_| "Dropbox session could not be read. Reconnect in Settings".into()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("Could not read Dropbox session: {e}")),
    }
}

fn save_session(session: &Session) -> Result<()> {
    let path = session_path();
    let parent = path.parent().unwrap();
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    serde_json::to_writer(file.as_file_mut(), session).map_err(|e| e.to_string())?;
    file.as_file().sync_all().map_err(|e| e.to_string())?;
    file.persist(path).map_err(|e| e.error.to_string())?;
    Ok(())
}

async fn exchange(form: &[(&str, &str)]) -> Result<TokenResponse> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|e| e.to_string())?;
    let response = client
        .post("https://api.dropboxapi.com/oauth2/token")
        .form(form)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|_| "Could not reach Dropbox to authorize access")?;
    if !response.status().is_success() {
        return Err(format!(
            "Dropbox rejected authorization (HTTP {}). Check the App key and reconnect in Settings",
            response.status().as_u16()
        ));
    }
    let token: TokenResponse = response
        .json()
        .await
        .map_err(|_| "Invalid Dropbox token response")?;
    if token.access_token.is_empty() || token.expires_in == 0 {
        return Err("Dropbox did not return a usable access token".into());
    }
    Ok(token)
}

fn cached_access(token: TokenResponse) -> Access {
    Access {
        token: token.access_token,
        expires: Instant::now()
            + Duration::from_secs(token.expires_in.saturating_sub(60).min(86400)),
    }
}

pub async fn access() -> Result<Option<String>> {
    let mut cached = ACCESS.lock().await;
    if let Some(access) = cached
        .as_ref()
        .filter(|access| access.expires > Instant::now())
    {
        return Ok(Some(access.token.clone()));
    }
    let Some(session) = session()? else {
        return Ok(None);
    };
    let token = exchange(&[
        ("grant_type", "refresh_token"),
        ("client_id", &session.app_key),
        ("refresh_token", &session.refresh_token),
    ])
    .await?;
    let access = cached_access(token);
    let result = access.token.clone();
    *cached = Some(access);
    Ok(Some(result))
}

fn authorization_url(app_key: &str, verifier: &str, state: &str) -> Url {
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let mut url = Url::parse("https://www.dropbox.com/oauth2/authorize").unwrap();
    url.query_pairs_mut().extend_pairs([
        ("client_id", app_key),
        ("response_type", "code"),
        ("redirect_uri", REDIRECT),
        ("token_access_type", "offline"),
        ("scope", SCOPE),
        ("code_challenge", &challenge),
        ("code_challenge_method", "S256"),
        ("state", state),
    ]);
    url
}

fn callback_result(request: &str, state: &str) -> Option<Result<String>> {
    let mut words = request.split_whitespace();
    if words.next() != Some("GET") {
        return None;
    }
    let target = words.next()?.strip_prefix('/')?;
    let url = Url::parse(&format!("http://127.0.0.1/{target}")).ok()?;
    if url.path() != "/oauth2callback"
        || !url
            .query_pairs()
            .any(|(key, value)| key == "state" && value == state)
    {
        return None;
    }
    if url.query_pairs().any(|(key, _)| key == "error") {
        return Some(Err("Dropbox sign-in was cancelled or denied".into()));
    }
    Some(
        url.query_pairs()
            .find(|(key, value)| key == "code" && !value.is_empty())
            .map(|(_, value)| value.into_owned())
            .ok_or_else(|| "Dropbox did not return an authorization code".into()),
    )
}

async fn callback(listener: TcpListener, state: &str) -> Result<String> {
    tokio::time::timeout(Duration::from_secs(180), async {
        loop {
            let (mut socket, _) = listener.accept().await.map_err(|e| e.to_string())?;
            let mut request = String::new();
            if !matches!(tokio::time::timeout(
                Duration::from_secs(2),
                BufReader::new(&mut socket).take(8192).read_line(&mut request),
            ).await, Ok(Ok(_))) {
                continue;
            }
            let result = callback_result(&request, state);
            let (status, body) = if matches!(result, Some(Ok(_))) {
                ("200 OK", "Dropbox authorization received. Return to EditHub.")
            } else {
                ("400 Bad Request", "Invalid or cancelled Dropbox authorization.")
            };
            let response = format!("HTTP/1.1 {status}\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len());
            let _ = tokio::time::timeout(Duration::from_secs(2), socket.write_all(response.as_bytes())).await;
            if let Some(result) = result {
                return result;
            }
        }
    }).await.map_err(|_| "Dropbox sign-in timed out")?
}

#[tauri::command]
pub async fn dropbox_status() -> Result<bool> {
    Ok(session()?.is_some())
}

#[tauri::command]
pub async fn connect_dropbox(app_key: String) -> Result<()> {
    let _sign_in = SIGN_IN
        .try_lock()
        .map_err(|_| "Dropbox sign-in is already open")?;
    let app_key = if app_key.trim().is_empty() {
        session()?
            .map(|session| session.app_key)
            .unwrap_or_default()
    } else {
        app_key.trim().to_owned()
    };
    if app_key.is_empty()
        || app_key.len() > 128
        || !app_key
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
    {
        return Err("Enter a valid Dropbox App key".into());
    }
    let listener = TcpListener::bind("127.0.0.1:53682")
        .await
        .map_err(|e| format!("Could not open the Dropbox sign-in callback on port 53682: {e}"))?;
    let verifier = format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    );
    let state = uuid::Uuid::new_v4().to_string();
    open::that_detached(authorization_url(&app_key, &verifier, &state).as_str())
        .map_err(|_| "Could not open Dropbox sign-in in your browser")?;
    let code = callback(listener, &state).await?;
    let mut token = exchange(&[
        ("grant_type", "authorization_code"),
        ("client_id", &app_key),
        ("code", &code),
        ("code_verifier", &verifier),
        ("redirect_uri", REDIRECT),
    ])
    .await?;
    let refresh_token = token
        .refresh_token
        .take()
        .filter(|token| !token.is_empty())
        .ok_or("Dropbox did not grant background access")?;
    let mut cached = ACCESS.lock().await;
    save_session(&Session {
        app_key,
        refresh_token,
    })?;
    *cached = Some(cached_access(token));
    Ok(())
}

#[tauri::command]
pub async fn disconnect_dropbox() -> Result<()> {
    let _sign_in = SIGN_IN
        .try_lock()
        .map_err(|_| "Finish or cancel Dropbox sign-in first")?;
    let mut cached = ACCESS.lock().await;
    match std::fs::remove_file(session_path()) {
        Ok(()) => (),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
        Err(e) => return Err(e.to_string()),
    }
    *cached = None;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_accepts_the_matching_dropbox_callback() {
        assert!(callback_result(
            "GET /oauth2callback?code=test&state=wrong HTTP/1.1",
            "state"
        )
        .is_none());
        assert!(callback_result("GET /other?code=test&state=state HTTP/1.1", "state").is_none());
        assert!(callback_result(
            "GET /oauth2callback?error=access_denied&state=state HTTP/1.1",
            "state"
        )
        .unwrap()
        .is_err());
        assert_eq!(
            callback_result(
                "GET /oauth2callback?code=a%2Bb&state=state HTTP/1.1",
                "state"
            )
            .unwrap()
            .unwrap(),
            "a+b"
        );
    }

    #[test]
    fn requests_read_only_background_access_with_pkce() {
        let url = authorization_url("test-key", "test-verifier", "test-state");
        let args: std::collections::HashMap<_, _> = url.query_pairs().into_owned().collect();
        assert_eq!(args["redirect_uri"], REDIRECT);
        assert_eq!(args["token_access_type"], "offline");
        assert_eq!(args["scope"], SCOPE);
        assert_eq!(args["code_challenge_method"], "S256");
        assert_eq!(args["code_challenge"].len(), 43);
        assert!(!args.contains_key("client_secret"));
    }
}
