# Privacy Policy for Thestia

**As of: October 2026** · Version 17 (v0.10.0)

Thestia is a privacy-conscious open-source project (AGPLv3). Protecting
your personal sphere comes first: no advertising trackers are used, no
behavioural profiles are created, and no user data is sold to third
parties.

---

## 1. Principles and data controller

**Contact:** Questions about the processing of your data, access,
rectification or erasure can be directed to the in-app bug report form
(*Settings → Privacy → Report a bug*) or to the **contact address
`datenschutz@thestia.de`**. To request erasure, state your user ID -
then the residual data listed above is removed as well.

The data controller within the meaning of the GDPR is **Thestia**, the
project by Thoralf Illg (store listing: *Thestia*). To get in touch
about all privacy-related matters: via the **in-app bug report form**
(Settings) or by e-mail to `datenschutz@thestia.de`. For the provider
identification pursuant to Sec. 5 DDG (Imprint), see
<https://auth.thestia.de/en/impressum>.

Server-side processing takes place in the EU region of Supabase
(contractual obligations as a processor pursuant to Art. 28 GDPR, see
section 6). The source code is publicly viewable and can be self-hosted;
if someone runs their own instance, that instance is itself the data
controller, under its own name.

**Principles (Art. 5 GDPR):** data minimisation, purpose limitation,
storage limitation, data protection by design and by default (E2E,
on-device) and transparency. There is **no** advertising ecosystem
integration, **no** tracking pixel and **no** cross-user behavioural
analysis.

## 2. Data collected and processing purposes

| Category | Data | Purpose | Erasure |
|---|---|---|---|
| Account data | Name, e-mail, date of birth, gender | Account management, child safety filter (enforced server-side) | With account deletion |
| Location data | Federal state as well as coordinates, rounded to a 5 km grid before being stored | Distance calculation; the coordinates are kept exclusively in a table that only the owner can read and never leave the server | 30 days after the last location write; with account deletion |
| Parental supervision | E-mail address of one parent, status of the approval, time window of permitted use, four-digit PIN (stored as a hash only), timestamps of the request, confirmation and revocation | Consent of those with parental responsibility for accounts aged 16/17; limitation of the usage time; notification of the parents about new sparks. The parent is an **approver, not a user** - they have no account and see neither messages nor profiles | With the end of the approval; the events used for notifications are deleted after they have been sent |
| Distance display | Distance in steps of 10 km, only if the person concerned has **switched it on**; below 5 km nothing is displayed. **For 16- and 17-year-olds the display is excluded - even if they switch it on** | Other users see only the step, never a value in metres or kilometres. Without switching it on they see no distance at all. The block for minors lives in the database (`profile_distance_km`, migration 163) and is based on the verified age | – |
| Place of residence | Not collected | Since v0.10.0 no place, no city and no postcode area is stored or displayed - only the federal state | – |
| **Information from which your sexual orientation can be inferred** (derived, not collected): who you are looking for, what you are looking for, your interests, your gender | Prerequisite for the matching; Art. 9 (2) (a) GDPR - processing only with your explicit consent (see section 2b) | with the account deletion; can be deleted individually at any time |
| Profile details | Bio, interests, audio introduction, habits (smoking/alcohol/drugs), mood, music taste, **profile picture** (see section 3a) | Matching suitable contacts ("sparks") | With account deletion |
| Device list | Device model (manufacturer + model identifier, e.g. "Samsung SM-S921B"), platform, app version, timestamp of the last login; on a sign-in from a **new** device additionally a notification email with the device name, the app version and the time | Display "Where am I logged in?" + "Sign out everywhere" (migration 071/078); no location, no serial number, no advertising ID | Automatically on sign-out; with account deletion |
| Preferences | Search radius, age range, gender filter, "I'm looking for", colour world, UI switches (Blind Mode, visibility, notifications) | Restoration after a reinstall (migration 066/071/074/076) | With account deletion |
| Push tokens | FCM token (Play only) resp. UnifiedPush endpoint (F-Droid) | Delivery of push signals **without any message content** | With account deletion / sign-out |
| Appearance features (Transit Spark) | Category and value of a feature (clothing per category, headwear, shoes, accessories, hair colour/length/style, eye colour) as well as the associated colour specification, each as a list of up to eight values | Feature matching in Transit Spark: "what I noticed about you" against "what you say about yourself". Only the selection is transmitted, not the purpose | After 24 hours (cron `cleanup-transit-signals`) |
| Country | Country of residence (DE, AT, CH and others) | Display of the country in the profile and for match partners | With account deletion |
| Device identifier | Random identifier of the device (UUID, no MAC address, no advertising ID) | Registration of your own devices for the end-to-end encryption | Automatically on sign-out; with account deletion |
| Image review hash | SHA-256 hash of a chat image you sent, together with the identifier of the recipient | Proof that a reported image really did travel through a chat (abuse protection against arbitrary reports) | With account deletion |
| Location timestamp | Time of the last location check | Plausibility check (implausible changes of location) | With account deletion |
| Marker of the account | MD5 hash of the account identifier | Prevents a deleted account from being registered again | Persists permanently, without any clear name |
| Verification | Self-recording with image **and** sound to estimate the age. The video is **encrypted on the device** (AES-256-GCM) and only the ciphertext is transmitted; the key is stored in a table to which the app has no access. Purpose: age check for child safety and the 18+ release of Transit Spark. In case of rejection the video and key are deleted, otherwise at the latest 30 days after submission (section 7). Only a manual review by the administration creates a temporarily decrypted copy, which is deleted automatically after 20 minutes |

## 2a. Sign-in from a new device

When you sign in from a device we do not know yet, we send you an email.
It names **which** device it was (model, app version) and **when** (time).
That way you notice a foreign sign-in without anyone having to know your
password.

The check whether it is a new device happens on our server - not in the
app. An attacker with your password can therefore neither suppress nor
prevent the mail.

We send at most five such emails per account and hour. Directly after
registration there is none: the first sign-in is the registration itself.

When you sign in from a new device, you can see under
*Settings → Privacy & account → Devices* which devices belong to your
account, and log out foreign sessions.

## 2b. Information from which your sexual orientation can be inferred

**This has to be stated explicitly, because these are special category
data.**

Thestia does **not** ask you for your sexual orientation. But it can be
inferred from what you enter - in a dating app that is unavoidable, because
the whole point of the app is to bring together people whose wishes
match. Together, these details allow conclusions about your sexual
orientation:

| Detail | What it reveals |
|---|---|
| **Who you are looking for** (`gender_preferences`: "men", "women", "all") | whether you are looking for men, women or everyone |
| **What you are looking for** (`relationship_type`: "a relationship", "casual", "open") | the orientation of your wish |
| **Your interests** (e.g. "romance", "erotic") | the kind of contact you are looking for |
| **Your own gender** (`gender`) | combined with the above, the orientation |

**Legal basis:** These are data of a **special category** under
**Art. 9 GDPR** - the processing is therefore only permissible because
you have **explicitly consented** (Art. 9 (2) (a)). You give that
consent **by registering**; the notice about it is shown in the
registration form. You can withdraw it at any time - see section 8.

**What this means in practice:**

* We do not ask for the orientation, and we do not store it as a field of
  its own.
* We do not derive it from your behaviour and we sell nothing on. The
  matching calculation uses your details to show you suitable people -
  nothing more.
* We do not show other people your details in the form "is looking for
  men". They see your profile, your interests and (once you have
  consented) your photos - but not your search preferences.
* If you delete the details (section 7), the conclusions are gone too:
  the filters are reset to the default.

**Important:** We do not go without these details. A dating app without
the possibility to say who you are looking for would not be a dating
app. We simply say it openly.

## 3. End-to-end encryption (Signal protocol)

All regular chat messages, images and voice calls between users are
encrypted end-to-end via the **Signal protocol**. Neither the operators
nor any intermediary servers can view the message contents.

- **Transmission path:** A direct peer-to-peer connection (WebRTC) is
  attempted; if it does not succeed, the server takes over **solely the
  transport of the encrypted ciphertext** (relay fallback). The
  encryption is end-to-end and identical in both cases - the server
  never sees or processes any plaintext. This has no effect on the
  connection quality, and none on privacy either.
- Identity and session keys are kept in the encrypted device keystore
  (Android Keystore / iOS Keychain).
- An optional, **password-encrypted key backup** (PBKDF2 + AES-256-GCM)
  allows you to switch devices; the key is held exclusively by the user.
  Losing both the backup **and** the password is irreversible - no data
  recovery by the team is possible from it.

## 3a. Encrypted profile pictures (new as of v0.8.x)

Profile pictures are **already encrypted on your device** with
AES-256-GCM before they are uploaded. The server (Supabase Storage,
private bucket) stores nothing but the ciphertext - even in the event of
a storage incident the images are unreadable. The decryption key is
generated randomly per image and carried along in your own profile
entry; only people who are allowed to see your profile (visibility
setting + age protection) download and decrypt the image locally. In
addition, before every upload a **purely local NSFW pre-check** runs
(ONNX model on-device): image bytes, scores and result are processed
exclusively on the device; if it does not pass, the image never leaves
your device (an objection with a manual review by the team is possible).

## 3b. Near-field radio (BLE, "Transit Spark")

Transit Spark uses Bluetooth Low Energy so that two people can meet
nearby without having to talk to each other. Radio metadata is processed
in the process.

**What is sent:** an ephemeral, random token (no device ID, no name, no
MAC address of the device). The operating system's stack assigns a
resolvable private address for the advertising; the app does not set a
fixed address.

**What is received:** since v0.9.2 the scanner is filtered to the
manufacturer's ID of the app. Previously it processed every Bluetooth
signal in range (watches, headphones, beacons); that has been corrected.
Since 6 November 2026 a received signal is additionally checked
strictly: only a complete Thestia token (20 hex characters after the
"WST1" marker) counts. Everything else - every foreign Bluetooth device -
is discarded and never reaches the list of encounters. The counter "X
Thestia signals in range" therefore counts real app users only.

**Location permission (Android 11 and older):** on these system versions
Android additionally requires the precise location permission for
Bluetooth scanning - without it the operating system silently blocks the
scan. The app therefore declares this permission only for Android 11
and older (`maxSdkVersion="30"`). From Android 12 on, `BLUETOOTH_SCAN` is
sufficient; there the location is **not** requested for the radar at
all. The location is neither stored nor transmitted for the radar - it
only serves to let the operating system permit the scan. Before the
request the app shows a short disclosure (as it does for camera and
microphone), telling users what it is about.

**What stays local:** encounters (token, timestamp, strongest RSSI) are
stored exclusively on the device, with a retention period of 45 minutes,
after which they are deleted automatically. They are not transmitted to
the server.

**What the server sees:** as soon as a person starts the radar scan,
their own anonymous token is stored on the server - without that no
encounter could take place at all. Only once both people have explicitly
confirmed ("exchanged glances") are the most recently observed tokens,
the selected features and the self-description given by the person
transmitted for review. The server checks the age and the blocked
status. No device identity can be derived from a token.

**Features in plaintext:** The selected features (category, value,
colour) and the free-text self-description are stored as plaintext in
`transit_signals` - unlike chat messages, which are transported as
ciphertext. The reason: the features are the matching input, and a
ciphertext could not be compared. They are intended only for the other
party and are deleted after 24 hours.

**Features of a third person:** The features you noticed about another
person are appearance data about someone who does not know anything
about it themselves. They are used exclusively for Transit matching, are
not displayed and are not passed on to third parties. The
self-description (your own appearance), by contrast, is seen only by the
person you have met.

**Reduction of the radio fingerprint:** The advertising is restarted at
irregular intervals and the encounter token is not switched on a rigid
time grid. The transmission pattern is therefore not constant across
sessions. This does not amount to complete protection against radio
sniffing: Bluetooth is a radio medium and is observable in its
surroundings.

**No tracking:** Transit Spark does not determine any position via
radio. The location is used only for the distance display of profiles
and is deleted server-side after 30 days (migration 129, cron
`purge_stale_locations`).

**What is stored is not the location but a grid point:** Since v0.10.0
coordinates are rounded to a grid of 5 km before being stored - enforced
server-side, not only in the app. Anyone living in a country with
millions of inhabitants cannot derive their place of residence from this
data. The place itself is not collected, displayed or stored; only the
federal state is visible.

**The verification location lies on the same grid:** For the age check
the app stores a location (in the device's keystore, not on the server).
That location is also rounded to the 5 km grid before it is stored - on
every system version. This matters because on Android 11 and older the
precise location permission is technically required (for Bluetooth
scanning), and the operating system does not yet offer a choice between
"approximate" and "precise" there. The app therefore never keeps an
exact location - and the accuracy of 5 km is sufficient for its purpose
(the city is derived from it, nothing more precise).

**The distance display requires consent:** The display is off by default
and has to be switched on per person. Off means `null` server-side - no
residual distance is calculated back from the federal state. Switched on
means: others see a step of 10 km, not a number.

## 3c. Local contact data ("Connect to others") and safety education

**Contact data (voluntary, exclusively local):** In "Connect to others"
you can voluntarily enter a phone number as well as handles for Signal,
Threema, Instagram, Snapchat, Discord or your own apps. This information
is stored **exclusively on your device** in the encrypted keystore
(Android) resp. in the Keychain (iOS) - in a separate storage area
(`SecureNamespaces.contacts`). It is **not transmitted to Supabase, to
the Thestia servers or to third parties** and is not backed up
server-side. Neither a device change nor a reinstall transmits it.

The information is shared only if you actively tap "Share" or "Copy" in
the app: "Share" hands the text you generated to the operating system
(share sheet), "Copy" puts it into the clipboard. What happens to the
text afterwards is outside our sphere of influence. You can remove the
information in the form at any time and save it again; deleting the app
data removes it as well. Phone numbers are checked for a valid format
before being stored, but are not sent to a server for validation.

**Safety education before the setup:** After the e-mail confirmation the
app asks whether you have used a dating app before and whether you are
aware of the dangers of online dating. The answers (yes/no), the current
step and the start time of the education are stored **only locally** in
the app settings (SharedPreferences), so that the process can be
continued after a restart. They are not transmitted to the server and
are not used for profiling or advertising. The education takes at most
five minutes; the detailed version is available at
<https://auth.thestia.de/en/dating-sicherheit>.

## 4. Local chat history (optional) and local AI reflection chat (Sanctuary, planned from v0.10.0)

**Local chat history (since v0.8.x):** On request the app stores chats
encrypted (AES-256, SecureHive; key in the keystore) locally on the
device - you can choose between "Off", "200 messages per chat" and
"Complete history" (default). The data does not leave the device and can
be deleted at any time by deactivating it. The JSON data export contains
the history (inspectability/portability), the import restores it.

The reflection assistant described below is **planned for v0.10.0** and
is not yet part of this version; the description reflects the planned
state. All the commitments made in this section - local, without
transmission - only apply once it has been released.

As planned, it runs entirely locally ("on-device") on your smartphone.
All text inputs, uploaded screenshots and generated answers remain
exclusively on your device and are never transferred to external servers.

- Chat histories remain **volatile in RAM** or are optionally stored
  **purely locally, AES-encrypted** in Hive (default: volatile).
- The crisis detection (regex on suicide-related terms) runs exclusively
  locally; emergency contact details are then displayed (Telefonseelsorge
  0800 111 0 111 / 0800 111 0 222, Nummer gegen Kummer 116 111). **No**
  analysis or report data is generated.
- The "Report model quality" function transmits only the text excerpt
  released by the user as well as model metadata (model name,
  quantization, app version) - never complete chat histories.
- Model downloads (GGUF) are user-initiated and happen directly from
  Hugging Face; the app transmits no additional metadata in the process.

## 5. Reporting system and abuse protection

- Chat images are **never scanned server-side** in normal operation.
- If a recipient reports a received image, it is pre-assessed **locally
  on the device** using an ONNX model. The person reporting sees the
  result and decides: only after explicit confirmation is the image
  concerned transmitted to the administration for manual review. The
  image content is passed on to an **external AI service** (section 6)
  for automatic classification; no automatic decision about a report is
  derived from it.
- Reports are **pseudonymised**: the identity of the person reporting is
  never disclosed to the person reported (technically a SHA-256 hash,
  migration 069).
- Reports about insufficient model quality in the reflection chat contain
  only the text excerpt released by the user as well as model metadata.

## 6. Data disclosure and third-party providers

| Provider | Data | Purpose | Region |
|---|---|---|---|
| Supabase (EU region) | Account data, encrypted authentication tokens, profile data | Hosting of accounts, DB, Auth | EU (processing agreement via Supabase Europe B.V.) |
| Firebase Cloud Messaging (Play Store version only) | Push token, "silent" push signals | Delivery signal; the contents are then loaded locally via WebRTC/E2E | Google infrastructure (processes only the token) |
| UnifiedPush (F-Droid version, e.g. ntfy) | Push endpoint | Google-free push delivery | Freely selectable (can be completely self-hosted) |
| Spaceship (domain and mail hosting) | Recipient address, for incoming mails the sender, for outgoing mails the content of the transactional mail; when forwarding the child safety report the full report content | Forwarding of incoming mails to the mailbox of the contact person; dispatch of the transactional mails via the provider's mail relay | EU (Netherlands/USA, depending on the relay) |
| Brevo | E-mail address; for a bug report additionally the description you gave, device information, your user ID and up to five screenshots; for an image report the reported image | Transactional e-mails (confirmation, password reset, bug report), copy to support, manual review of reported images | EU |
| Mailjet (optional, currently not configured) | E-mail address, confirmation and confirmation links | Dispatch of the transactional e-mails (registration confirmation, password reset), if Mailjet is configured; otherwise Brevo sends them | France (EU) |
| Cloudflare | CAPTCHA token (Turnstile) | Bot protection | Global (EU PoP preferred) |
| Netlify | CAPTCHA interstitial page, privacy policy | Hosting of the sign-in/CAPTCHA page and of the published privacy policy | Global |
| Hugging Face | When reporting an image: the **image content** (for automatic classification as decent or unobtrusive); when downloading an AI model file: no personal data | Automatic pre-assessment of reported images; otherwise exclusively the optional, user-initiated download of freely available AI model files (GGUF) | Global |
| STUN servers (nextcloud/Hetzner, miwifi/OVH, voipgate, voipstunt) | Your IP address | Determination of the public address for the direct connection attempt during video and voice calls; no content is transmitted via these servers | Germany, France, Netherlands (EU) |
| Codeberg e.V. (planned from v0.12.0) | No personal data | Tracker-free hosting of the Flutter web artefacts (static files) | Berlin, Germany |
| Liberapay (only if you use the donate button) | **None from the app.** The app merely opens a link in your browser. The payment itself runs entirely on the provider's website; the app receives neither a confirmation nor a donor ID and does not even know whether a donation was made | Voluntary donation to support the project | EU (Netherlands) |

**Financial data:** The app collects **no** payment or financial data.
There is no in-app purchase, no subscription and no payment system in the
app. The only financial procedure is the voluntary donate button in the
profile: it opens the provider's website in your browser. The app
transmits nothing in the process - no card details, no buyer ID, no
transaction confirmation, no payment status. It does not even know
whether a donation was made (which is why there is deliberately neither
a donor confirmation nor a donor badge in the app).

**No** disclosure to advertising networks, data brokers or analytics
services. **No** use of Google Analytics, Crashlytics or similar products
(bug reports run through the in-app form and contain only the
information the user has checked).

## 7. Retention periods and account deletion

You always have the right to the complete erasure of your account
(**Art. 17 GDPR - right to erasure**) - and you can also delete
individual data without giving up your account.

**Delete data without deleting the account (v0.10.0):** Under *Privacy &
account* you will find the entry **Delete data**. You tick what should
disappear and confirm. The account, your e-mail address and your
password remain - you can still sign in.

The following are available for selection: profile photos, location data
(coordinates and federal state), profile details (bio, interests, music,
introduction, audio, habits), likes, sparks, the messages you sent,
your device list including passkeys and push keys, mood and history,
your reports and error reports, Transit Spark data as well as the
parental approval. "Delete all data" removes all data belonging to the
account and leaves the account itself in place.

The erasure is **irreversible** - there is no restore. Where the other
party is affected as well, this is stated for the respective category:
deleting a spark also ends the chat for the other person; received
messages are data of the other person and disappear there.

The erasure takes place on the server immediately.

- When the in-app function **"Delete account"** is executed (under Privacy
  & account, with 2FA confirmation), all personal data on the servers is
  removed promptly and irreversibly: profile, message metadata,
  likes/matches, report references, device list, push token, Signal
  prekeys and storage files (avatar/audio).
- Local databases on the device are cleaned up in the same pass (E2E
  identity, verification data, temp files).
- Technically necessary residual data (e.g. ban entries against the
  circumvention of child safety blocks) is only stored for as long as it
  is legally or purpose-bound necessary (Art. 6 para. 1 lit. f GDPR) and
  is deleted afterwards.
- Ephemeral web guest sessions (planned from v0.12.0) destroy themselves
  server-side after 24–48 hours without a trace.
- Transit Spark signals (tokens, features, self-description) are deleted
  automatically after 24 hours (cron `cleanup-transit-signals`).
- The verification video is stored encrypted (only the ciphertext is kept
  permanently in storage). During the review by the administration a
  decrypted copy is created temporarily, which is deleted automatically
  after 20 minutes. **The video itself is kept for 30 days after the
  approval of the verification** (migration 171; the period previously
  started at the submission - a video that waited weeks for the review
  was already deleted on the day of the approval). If a verification
  lies undecided for more than 90 days, the video is deleted as well -
  the review needs it, but it may not lie there without limit. It is
  deleted together with its key (cron
  `cleanup-verification-videos`).

## 7a. Delete data: the public pages

Two pages on the web are available to you and describe the ways in which
you can request the erasure of your data:

- **Delete data** (`https://thestia.de/en/daten-loeschen`): the steps for
  deleting individual categories and for the complete erasure, the kind
  of the deleted and of the retained data with their retention periods.
- **Parents and young people** (`https://thestia.de/en/eltern`): how
  parental consent for 16- and 17-year-olds works, which data is
  processed in the process and which rights the young person retains.

## 8. Your rights (Art. 15–21 GDPR)

- **Access (Art. 15):** The in-app data export ("Export my data")
  provides the personal data stored on your device as a JSON download.
  Data that exists only on the server (e.g. matches, likes, reported
  content, your device list) we retrieve on request - write to us about
  it.
- **Rectification (Art. 16):** All profile fields can be freely edited
  and deleted in the app.
- **Erasure (Art. 17):** See section 7. Individual data categories can be
  deleted in the app under *Privacy & account* without giving up the
  account. For everything else (including data that exists only on the
  server) a message to us is sufficient.
- **Withdrawal of consent (Art. 7 (3), Art. 9 (2) (a)):** You can
  withdraw your consent to the processing of the special categories at
  any time (see section 2b). We then stop the processing; the data
  concerned is deleted unless there is another legal basis. The
  withdrawal does not affect the lawfulness of the processing carried
  out until then.
- **Restriction/objection (Art. 18/21):** Via the contact options in
  section 1.
- **Data portability (Art. 20):** JSON export via the in-app function.
- **Right to lodge a complaint (Art. 77):** With a supervisory authority,
  e.g. the state data protection authority.

## 9. Child and youth protection

Use is permitted from **16 years** of age. 16- and 17-year-olds are
strictly separated server-side: they see exclusively other minors, photos
are technically invisible to adults (Blind Mode enforced), and the age
filters are limited server-side (migration 056). Date of birth is
processed to enforce this child protection (Art. 6 para. 1 lit. c/f) and
is never displayed to other users (only a rounded age).

**Coarse distance (v0.10.0):** 16- and 17-year-olds do not disclose
**any distance** - not even the approximate one in 10 km steps. The block
lives in the database (`profile_distance_km`, migration 163) and is based
on the **verified** age; in the app the switch is locked for this age
group. In an environment where people arrange to meet others by
proximity, an approximate value says more than it does among adults -
that is why it stays off here. For adults nothing changes.

**Parental approval for 16- and 17-year-olds (v0.10.0):** For accounts
in this age range, Thestia requires the consent of those with parental
responsibility. The consent is **voluntary**: under Sec. 3a JUG a person
can consent themselves from the age of 16, and nobody is prevented from
using the app because the consent is missing.

Here is how it works:

- The young person enters the e-mail address of a parent. It must be **a
  different one** from their own account address - otherwise the young
  person would register themselves as their own parent.
- The parent receives an e-mail with a link, confirms the approval there
  and can revoke it at any time with a single click. The link contains an
  access key that is only stored as a hash and is invalid after 24 hours.
- **The parent has no account.** They see exclusively what is necessary
  for the supervision: whether an approval exists, what rhythm the
  notifications have and whether the usage time is limited.
- **The parent's e-mail address is deleted when the approval ends.** Once the
  approval has ended, the address is no longer needed: there are no more
  notifications and no more access to the parent portal. It is then removed from
  our data. If the young person chose a grace period ("keep it for one more
  month"), the approval only ends after that period, and the address is only
  deleted then.
- **Notifications:** when a spark arises between the young person and
  another person (a mutual "I like you" - not just a single like), the
  parent receives a short message. They set the frequency themselves:
  daily, weekly, monthly or not at all. **We name no names, no profiles
  and no contents** - the parent only learns *that* a spark has arisen.
  Anyone who does not want that does not learn it.
- **Usage time:** the parent can define a time window in which the app
  may be used. This setting is protected by a four-digit PIN; the PIN is
  only checked on the server and is not stored on the young person's
  device. The young person therefore cannot change it themselves - but
  they also cannot guess it (the check is blocked for one hour after five
  failed attempts).
- **At 18 the obligation to consent ends.** Then the young person
  decides themselves: end access, keep it for 1 to 6 months, or keep it
  for now. Even after 18 the section remains visible in the settings, so
  that the approval from the 16/17 period can be tidied up.

We log every request, confirmation and every revocation with the time
(Art. 5 para. 2 GDPR, accountability). We do **not** pass the young
person's own data on to the parent.

**What the usage time is not:** it is a house rule on the young person's
device. It prevents the accidental overrun - but it is not a technical
prohibition. Anyone with a rooted device or who builds the app
themselves can get around it. That is a fact we do not gloss over.

**Transit Spark is exempt from this and can only be used from 18 years
of age.** The block is in two places, because one alone is not enough:

- **On the device**, fail-closed: if the date of birth is missing, the
  person is not deemed to have proven adulthood and is blocked - not let
  through, that is.
- **In the database**, for the radar, the matching and getting in contact
  (`transit_spark_adult()`, migration 131). There the person found is
  checked as well, because the usual age-band rule would otherwise also
  allow 16-year-olds in. Old RPC signatures were removed, because they
  would have circumvented the block.

A prerequisite for the release is the age verification from section 2:
it uses camera **and** microphone and asks for both only after an
explanatory dialogue that reveals what they are used for.

**Decisive age (v0.10.0):** For child protection, the age that was
**verified** by video counts - not the entry in the profile. An account
without verification appears in no encounter list; the entry in the
profile only takes effect after the verification. Anyone who registers
with a false date of birth is therefore not treated as an adult, but is
not even suggested in the first place.

**Visibility in both directions (v0.10.0):** Anyone who is 16 or 17
years old sees exclusively people who are also 16 or 17 years old - never
an adult. And an adult never sees a person under 18. This applies in
both directions, not just in one: the filter is based on a comparison of
both ages. The age range in the profile is limited downwards to 10 years
below your own age (and never below 18 once you are of age) - whoever
chooses a larger age difference does not get it delivered server-side.

**Mandatory child safety standards (v0.10.0):** Google Play requires four
things for dating, social and random chat apps, independently of an age
restriction, which we provide via the app and via a public page:

- An **explicit prohibition** of child abuse and the sexual exploitation
  of children (CSAE/CSAM) in the community standards accepted in the
  app.
- A **named contact person** for reports of child abuse.
- A **described reporting channel**: in the app via the report with the
  reason "Report of child abuse (CSAE/CSAM)", by e-mail to the contact
  person, or in case of immediate danger directly to the police or the
  emergency number.
- A documented **process upon becoming aware** of such cases: priority
  review, blocking of the account until the review is complete, removal
  of the content and reporting of confirmed cases to the competent
  authorities.

The public page is at <https://auth.thestia.de/en/kinderschutz>. The
contact person is named on that page.
## 10. Threat model and risk assessment

The technical assessment of the processing is public: you can find the
threat model at <https://auth.thestia.de/threat-model.md>. The risks
pursuant to Art. 35 GDPR (data protection impact assessment) exist as a
draft and have not yet been legally reviewed; we make them available on
request. There are also the points named that Thestia deliberately does
**not** promise: radio metadata is technically observable, and end-to-end
encryption protects content, not communication patterns.

## 11. Changes to this policy

In the case of functional changes (new data categories, new providers)
this policy is updated in the app and in the repository; the change
history is traceable via the version line at the top of the document and
the git history.

---

### History

| Version | Date | Change |
|---|---|---|
| 22 | 2026-11 | **Retention of the verification video moved to the approval:** The period previously started at the upload - a video that waited weeks for the review was already deleted on the day of the approval. The videos are now kept for **30 days after the approval of the verification**; on a rejection for 30 days from the submission, and as a safety net for 90 days without a decision (migration 171). |
| 21 | 2026-11 | **Information from which the sexual orientation can be inferred explicitly disclosed:** The consent to the processing of these special categories (Art. 9 (2) (a) GDPR) is given by registering; the notice about it is shown in the registration form, the withdrawal in section 8. |
| 20 | 2026-11 | **Parental approval for 16- and 17-year-olds:** The consent of those with parental responsibility is requested (e-mail address of one parent, which must differ from the young person's own account address) and confirmed by the parent via a link. The parent is an approver, not a user - they have no account and see no profiles. They can set the notification about new sparks to a rhythm of daily/weekly/monthly/not at all (without names, profiles or contents), set a usage time via a PIN-protected time window, and revoke the approval at any time. At 18 the young person decides themselves. Every request, confirmation and every revocation is logged. |
| 19 | 2026-11 | **Coarse distance switched off for minors:** 16- and 17-year-olds do not display any distance - not even the approximate one in 10 km steps. The block lives in the database and is based on the verified age; the switch is locked in the app for this age group. For adults nothing changes |
| 18 | 2026-10 | **Verification now also enforced server-side:** The verification requirement for Find your Spark, Dating Hour and Transit Spark was previously only checked on the device - the server functions could be bypassed with a direct call. Now they enforce the verification themselves (migration 161). In addition, without an age entry an invented age of 26 years no longer applies; instead the age remains unknown and the 18+ block applies. The verification video is now also stored encrypted in the automatic release path - previously it was stored in plaintext in storage |
| 17 | 2026-10 | **Local contact data and safety education:** "Connect to others" stores phone number and handles voluntarily and exclusively encrypted on the device; no transmission to servers, no device sync. The new education before the setup stores answers and progress only locally. Complements section 3c and the public page `/en/dating-sicherheit` |
| 15 | 2026-10 | **Retention periods implemented and contact channel added:** The policy has announced the deletion of the verification video after 30 days since version 8 - but it was not implemented (there was no deletion job). The cron job `cleanup-verification-videos` (migration 160) now removes the ciphertext and the key after 30 days. In addition: the contact channel names a dedicated e-mail address, the data controller is named explicitly, and Spaceship is listed as a processor for the mail hosting. The sentence about the Transit Spark signals in section 7 was also broken |
| 16 | 2026-10 | **Security check (CAPTCHA) described in more detail:** The web view of the security check is only opened for this purpose and allows exclusively `auth.thestia.de` and Cloudflare's Turnstile services. Third-party cookies are **not** permitted there - therefore no session cookie from Cloudflare is stored, neither on the device nor in the app. In the error case the app shows the technical Turnstile code, so that an error can be assigned to a report instead of hiding it in a generic error message |
| 14 | 2026-10 | **Child safety standards:** Prohibition of child abuse (CSAE/CSAM) in the community standards, a dedicated report type in the app, a public child safety page with a named contact person and a reporting channel to the competent authorities. Required by Google Play for dating apps independently of an age restriction |
| 13 | 2026-10 | **Deletion URL and contact channel:** The deletion of the account is described on the web page <https://auth.thestia.de/en/konto-loeschen> (mandatory field in the Play Console) and the contact channel for access, rectification and erasure on request is named in section 1 |
| 12 | 2026-10 | **No TURN relay:** For video and voice calls STUN continues to be used exclusively - there is currently no relay provider that would be usable without a credit card and without self-operation. TURN support is recorded as a task on the roadmap and will only be implemented together with a provider and an entry in the privacy policy |
| 11 | 2026-10 | **TURN relay listed:** The relay server used for video and voice calls (Metered Open Relay) is now named as a third-party provider - along with the data it sees (IP address, time, duration of the forwarding) and the statement that the transmitted media remains end-to-end encrypted |
| 10 | 2026-10 | **Verified age is decisive:** The child safety filter now works with the age confirmed by video instead of the entry in the profile, and accounts without verification appear in no encounter list. Previously any age entry could be enforced unchecked |
| 9 | 2026-10 | **Youth protection tightened:** Visibility is now filtered in both directions - 16- and 17-year-olds see only peers, never an adult, and an adult never sees them. The age range is limited downwards to 10 years below one's own age. Minors are always checked by hand during video verification |
| 8 | 2026-10 | **Video encrypted:** The verification video is encrypted on the device with AES-256-GCM; only the ciphertext is stored. The key is stored in a table without client access. The earlier statements "encrypted only on the device" and "7 days" were wrong |
| 7 | 2026-10 | **v0.10.0 - Appearance features:** The features in Transit Spark are now divided into categories (top, bottom, head, shoes, accessories, hair, eyes) with one value per category, a search and their own colour palettes for hair and eye colour. The features are stored in plaintext in `transit_signals` - unlike chat contents, which are transported as ciphertext - and are deleted after 24 hours. Features you noticed about another person are used only for matching, are not displayed and are not passed on to third parties |
| 6 | 2026-10 | **v0.10.0 - Location new:** The place (city) is no longer collected, stored or displayed; only the federal state is visible. Coordinates are rounded to a 5 km grid before being stored in a table that only the owner can read. The distance display is off and has to be switched on; when switched on it shows steps of 10 km, below 5 km nothing at all. The columns `city`, `location_lat` and `location_lng` were removed from `profiles`. Erasure after 30 days remains |
| 5 | 2026-10 | v0.9.2: Age check with camera **and** sound correctly described as active (it was listed as "disabled"), 18+ block for Transit Spark, distance display corrected, Sanctuary marked as planned for v0.10.0 |
| 4 | 2026-09 | Encrypted profile pictures + on-device NSFW pre-check (3a), local chat history (3 modes), device model in the device list (078), preferences/UI sync (074/076) added |
| 3 | 2026-09 | Sanctuary (on-device AI), device list (071), web bridge/Codeberg (0.12.0 outlook), rights chapter added |
| 2 | 2026-08 | UnifiedPush, NSFW reporting workflow, ban entries |
| 1 | 2026-07 | First public version (beta) |
