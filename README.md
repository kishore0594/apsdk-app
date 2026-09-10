# Madhura Agro Traders — Store Management App

A Flutter app for tracking daily sales, credit collections, vendor-wise
credit history, inventory, and supplier records. Data lives in a shared
Firebase cloud database (Firestore), so two people signed in on separate
phones see the same live data — a sale or payment recorded on one phone
shows up on the other without any manual export/import.

## What's included

```
apsdk/
├── pubspec.yaml
├── .github/workflows/build-apk.yml   # Auto-builds the APK via GitHub Actions
└── lib/
    ├── main.dart                     # Firebase init, sign-in gate, bottom navigation
    ├── db/db_helper.dart             # Firestore data access (all reads/writes)
    └── screens/
        ├── login_screen.dart         # Email/password sign-in
        ├── dashboard_screen.dart     # Live stats, sales breakdown, low stock, aging credit
        ├── sales_screen.dart         # Daily sales + "New Sale" (cart, cash/credit/partial)
        ├── inventory_screen.dart     # Product list, add/edit, low-stock flags, stock history
        ├── vendors_screen.dart       # Credit customers, balances, date-wise ledger
        ├── suppliers_screen.dart     # Suppliers, balances owed, itemized purchases
        ├── todays_collections_screen.dart  # Detail view behind the dashboard's collections card
        └── data_sync_screen.dart     # CSV export (all data) / import (products, vendors, suppliers)
```

## One-time setup: Firebase (do this first)

The app needs a Firebase project to talk to — this is free and only takes
a few minutes, using the same Google account as your Gmail.

1. Go to **[console.firebase.google.com](https://console.firebase.google.com)**, sign in with your
   Google account, and click **Add project**. Name it anything (e.g.
   "Madhura Agro Traders") and finish the wizard (Google Analytics is
   optional — you can skip it).
2. In the project, go to **Build → Firestore Database** → **Create database**.
   Choose a location close to you, and start in **production mode**.
3. Once created, go to the **Rules** tab and replace the contents with:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if request.auth != null;
       }
     }
   }
   ```
   This means: anyone signed in can read/write the store's data, and nobody
   else can. Click **Publish**.
4. Go to **Build → Authentication** → **Get started**. Under **Sign-in method**,
   enable **Email/Password**.
5. Go to the **Users** tab → **Add user**. Create one account per person
   (their email + a password they'll use to sign into the app). Repeat for
   the second person.
6. Register the Android app: click the gear icon (⚙) next to *Project Overview*
   → **Project settings** → scroll to **Your apps** → click the Android icon.
   - **Android package name**: `com.yourstore.madhura_agro_traders`
     (must match exactly)
   - App nickname: anything you like
   - Skip the SHA-1 field (not needed for this setup)
   - Click **Register app**, then **Download google-services.json** — you'll
     need this file's contents in the next section. Skip the remaining
     wizard steps (the "Add SDK" ones) — that's already handled by the
     GitHub Actions workflow in this repo.

## One-time setup: GitHub secret

The `google-services.json` file identifies your Firebase project. It's not
committed to the repo (so it's not publicly visible) — instead it's stored
as a GitHub secret and written into the build automatically.

1. Open the `google-services.json` file you downloaded in a text editor,
   select all, and copy it.
2. On your GitHub repo, go to **Settings → Secrets and variables → Actions**
   → **New repository secret**.
3. Name it exactly `GOOGLE_SERVICES_JSON`, paste the file's contents into
   the value box, and click **Add secret**.

## Build the APK (same process as before)

Push the contents of this project to your GitHub repo (see the paste-into-
Codespace-terminal method from earlier, or plain git commands if you're
comfortable with them) — the existing `.github/workflows/build-apk.yml`
now also picks up the Firebase secret above automatically. Check the
**Actions** tab, download the APK from **Artifacts** once it's green, and
install it on both phones.

## Getting your existing inventory back in

Since this version stores data in the cloud instead of on-device, it starts
empty. After signing in on either phone for the first time:

1. Tap the ⇄ icon on the Dashboard → **Import Products CSV**
2. Pick the `madhura_products_import.csv` file (included alongside this
   README) — it has your original 31 products from the spreadsheet import
3. Once imported, it's in the shared cloud database — the other phone will
   see it immediately after signing in, no import needed there

## Notes & things worth knowing

- **This app now needs internet** to see live updates, though Firestore
  does cache data locally and will sync automatically once a connection
  returns if either phone goes briefly offline.
- **Cost**: Firebase's free tier (50,000 reads / 20,000 writes per day) is
  far more than a store with two users will use in normal daily operation.
  Worth knowing it isn't unlimited if the business grows significantly.
- **Only two accounts exist** right now, created manually in the Firebase
  console. If you need to add a third person later, repeat step 5 above —
  no code changes needed.
- **Security rules** are deliberately simple: any signed-in user can read
  and write everything. There's no separate "read-only" or "admin" role
  distinction between the two accounts.
- **APK signing**: still Flutter's default debug key (fine for installing
  directly on your own phones, not for the Play Store).
- **Editing a sale**: still not supported, to keep stock/credit math
  simple and audit-safe — recording a correcting entry is the current
  approach for mistakes.
- **CSV import** only covers products/vendors/suppliers (safe "catalog"
  data). Sales and credit/payment history are export-only, since importing
  them back could double-count stock or balances.
