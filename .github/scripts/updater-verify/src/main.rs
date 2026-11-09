use base64::{engine::general_purpose::STANDARD, Engine};
use minisign_verify::{PublicKey, Signature};
use std::{env, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let signature_path = PathBuf::from(env::args().nth(1).ok_or("missing signature path")?);
    let payload_path = signature_path.with_extension("");
    let key = String::from_utf8(STANDARD.decode(env::var("UPDATER_PUBLIC_KEY")?.trim())?)?;
    let signature =
        String::from_utf8(STANDARD.decode(fs::read_to_string(&signature_path)?.trim())?)?;
    let signature = Signature::decode(&signature)?;
    let version = env::var("UPDATER_VERSION")?;
    if !signature
        .trusted_comment()
        .split_whitespace()
        .any(|v| v == format!("version:{version}"))
    {
        return Err("signature is not bound to the app version".into());
    }
    PublicKey::decode(&key)?.verify(&fs::read(&payload_path)?, &signature, true)?;
    println!("Verified {}", payload_path.display());
    Ok(())
}
