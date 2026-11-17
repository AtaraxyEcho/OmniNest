# Privacy Notice

> This notice explains what data OmniNest involves, where it is stored, how it is used, and what you should be aware of.
> It applies to source distribution and self-hosted deployments. If a project-operated hosted service is ever offered, a corresponding notice will be added.

---

## 1. What OmniNest is

OmniNest is a self-hosted media center covering files, movies, music, photos, reading, sync, offline, and system management.
It is distributed as source code, and **your data stays on the server and storage you deploy yourself**.

**Core principle: the OmniNest project developers do not run any public server, and do not collect or upload your library contents.**

---

## 2. Where data is stored

- All business data (accounts, file metadata, tasks, configuration, etc.) is stored in the **PostgreSQL** database of your own instance.
- File and media bytes are stored in the content provider you configure (MinIO by default, or a local filesystem source you register).
- Client-side caches, playback history, etc. on Web / Android / Windows stay on your device.

All of this lives **within your own infrastructure**, and never passes through the OmniNest project developers.

---

## 3. Data types and how they are handled

| Data type | Stored in | How it is handled |
|---|---|---|
| Account credentials (username, password hash, JWT) | Your PostgreSQL | Passwords are stored as one-way hashes; sign-in state is verified via JWT |
| Library metadata (filenames, covers, tags, playback history, etc.) | Your PostgreSQL / local cache | Used only to provide features within your instance |
| File and media content | Your MinIO / local source | Uploaded or registered by you; developers never touch it |
| **Third-party music platform credentials (Cookie / Token)** | Your PostgreSQL | **Encrypted with AES-256-GCM before being stored**, see section 4 |
| Music platform user info (nickname, avatar, VIP status) | Your PostgreSQL | Used only to display account status within your instance |

---

## 4. Third-party music platform credentials

When you choose to connect a third-party music platform (such as NetEase Cloud Music):

1. You provide the platform Cookie/Token yourself; OmniNest stores it only within your instance, to forward your requests to that platform for the music you request.
2. Credentials are **not stored in plaintext**: they are encrypted with `CredentialCipher` (AES-256-GCM) and written to the `encrypted_credentials` field, with a key version for key rotation. The encryption key is provided by the deployer via configuration; without it, the credential feature is unavailable.
3. Credentials are decrypted and forwarded **only when you initiate a music platform request**, and never sent to any other third party.
4. You can **disconnect the platform** at any time within your instance, and the encrypted credentials are deleted.

> Note: third-party platform cookies are subject to that platform's terms of service. Please make sure your use of the credentials complies with the platform's rules.

---

## 5. Whether data is sent to third parties

- By default, OmniNest **does not send your data to any third party**.
- The only exception: when you connect a third-party music platform, credentials and your requests are forwarded to **that platform itself** (to fetch the music you requested).
- Optional components such as virus scanning (ClamAV) and image analysis, if enabled by you, keep data flowing only **within your own instance and components**.

---

## 6. Your rights

As a self-hosting deployer/user, you can:

- **Delete your account and data**: delete the account within your instance, or manage your own database and storage directly.
- **Disconnect third-party integrations**: revoke music platform credentials at any time.
- **Export and back up**: data is on your own infrastructure, so you can export, back up, or migrate it yourself.

Because your data lives on your own server, exercising these rights **does not depend on the OmniNest project developers**.

---

## 7. Responsibility and limits

- In a self-hosted environment, data security, backups, key management, public exposure, and access control are **the deployer's responsibility**.
- Data leaks or privacy risks caused by misconfiguration, over-broad permissions, or public exposure are **the deployer's responsibility**.
- The OmniNest project developers and contributors are not liable for privacy or data loss arising from use of or inability to use the software (see the README "Disclaimer").

---

## 8. A few reminders

- Please be mindful of the data and personal information regulations that apply where you are.
- If you open your instance to other people, please evaluate your own obligations as the operator.
- This document may change as the project evolves; important changes will be noted in the README or release notes.

---

_Last updated: 2026-09-22_
