<div align="center">
  <a href="https://aethercred.co.uk/">
    <img width="215" height="215" alt="AetherCred Logo" src="https://github.com/user-attachments/assets/cd1e2621-0f1a-45b2-b000-b4d21668d8c7" />
  </a>
</div>

# AetherCred - Entra ID Security Posture Dashboard

For detailed guidance, best practices, and remediation advice, visit [aethercred.co.uk](https://aethercred.co.uk/)

**AetherCred** is a PowerShell and HTML-based toolkit that provides a clear, actionable overview of your Microsoft Entra ID security posture. It collects and visualises key user, licensing, and policy data in an intuitive, shareable dashboard for both technical and non-technical stakeholders.

<img width="1772" height="1011" alt="AetherCred Dashboard Screenshot" src="https://github.com/user-attachments/assets/a64139dd-b317-485c-9ffa-80cec247b5cb" />

---

## Features

- **🔍 Comprehensive User Analysis**  
  Reports on user status, last sign-in, licence assignment, password expiry settings, and creation date.

- **🛡 MFA Classification**  
  Distinguishes between Modern (Passwordless, FIDO2, Authenticator App) and Legacy (SMS, Voice, TOTP) MFA methods.

- **📊 Security Scoring**  
  Assigns a user-level score (0–100) based on key risk factors including MFA, privileged roles, and password policies.

- **🚩 Risk Flagging**  
  Flags risky states like "MFA Not Registered", "Password Expiry Enabled", and "Never Signed In".

- **🔐 Privileged Role Identification**  
  Highlights users in critical administrative roles (e.g. Global Admin, Security Admin).

- **📈 Conditional Access Review**  
  Surfaces Conditional Access policies relevant to user security posture.

- **📁 Report Exports**  
  - HTML & JavaScript-based dashboard (offline, no server required)
  - CSV output (`AetherCred-Data.csv`)
  - PDF generation via browser (fully client-side with jsPDF)

---

## Requirements

- **PowerShell 5.1+**  
  (Note: PowerShell 7 is not fully supported.)
- **Microsoft Graph PowerShell SDK**  
  Install via:
  ```powershell
  Install-Module Microsoft.Graph -Scope AllUsers


## Getting Started

1. **Download Files**
   - `AetherCred-Core.ps1` (core script)
   - `AetherCred-Report.html` (dashboard template)

2. **Set Up Modules**
   - Create a folder named `Modules` in the same directory as `AetherCred-Core.ps1`.
   - Place supporting module scripts inside (e.g., `Run-SecurityReview.ps1`, `Run-ConditionalAccessReview.ps1`, etc.) - Download from the Modules folder if you haven't already

3. **Run the Script**
   Open PowerShell 5.1 and execute:
   ```powershell
   .\AetherCred-Core.ps1


---

## 🧠 Architecture Overview

### 🧩 Modular Design
Each review (security, licensing, conditional access) is handled by a separate `.ps1` module file under `/Modules`, promoting clarity and easy extensibility.

### 🔐 Graph API Connection
- Searches for an existing App Registration named `AetherCred`
- Automatically registers the app and assigns required permissions (e.g. `User.Read.All`, `Policy.Read.All`)
- Uploads a custom logo and sets redirect URIs
- Establishes a client credentials connection to Microsoft Graph via the app

### 🧠 Interactive Review Selection
After connection, you are presented with a menu to:
- Run all reviews
- Run specific reviews independently

The core script delegates execution to functions like `Invoke-SecurityReview` or `Invoke-LicensingReview`, depending on selection.

### 📦 Data Export & Processing
- All output data is serialised as JSON and compressed into a `.js` file (e.g., `AetherCred-Data.js`)
- Data is also saved as `.csv` for use with Excel
- A timestamp is embedded to show when the report was last generated

### 🖥 HTML Dashboard
- Fully offline and self-contained
- Loads `.js` files dynamically
- Uses JavaScript to populate metrics, tables, and charts
- Includes client-side PDF export via `jsPDF` and `autotable` libraries

### 🧹 Cleanup
All Graph sessions are properly disconnected after execution to prevent session leaks.

## PDF Report

The PDF export feature is fully **client-side** and requires no server. When you click **Download PDF Report** in the HTML dashboard:

1. The data is pulled directly from the `.js` files (e.g. `AetherCred-Data.js`, `AetherCred-CA-Data.js`)
2. A multi-page, landscape PDF is created in-browser
3. It includes:
   - Branded header (with logo and report title)
   - Page numbers
   - Timestamp of data
   - Full table of security attributes

This is powered by:
- [`jsPDF`](https://github.com/parallax/jsPDF)
- [`jspdf-autotable`](https://github.com/simonbengtsson/jsPDF-AutoTable)

**Note:** No data is ever sent outside your browser, ensuring complete privacy.

![PDF Preview](https://github.com/user-attachments/assets/f1e624d8-e1cf-406e-a696-14571641649f)

# Data Security

AetherCred is built with security and privacy in mind. Your tenant data is never transmitted to any third-party service at any point in the workflow.

### Key Principles

- **No External Data Transfer**  
  All data collected from Microsoft Graph stays **local** to your environment. The tool does not upload, sync, or transmit any information to external servers or APIs.

- **Offline Report Generation**  
  The HTML dashboard and all generated files (`.js`, `.csv`, `.pdf`) run entirely **in your browser**. No internet connection is required after initial data collection.

- **Client-Side PDF Export**  
  PDF reports are generated using client-side JavaScript libraries (`jsPDF`, `autotable`). Nothing is sent to any cloud service or external processor.

- **Controlled Permissions**  
  When using App Registration, you define exactly which Microsoft Graph permissions are granted, enabling compliance with the principle of least privilege.

- **No Data Retention**  
  AetherCred does not log or retain any data beyond what is saved explicitly by the user as output files (`.csv`, `.js`, `.pdf`).

By design, AetherCred operates as a **self-contained and auditable** security reporting tool, suitable for both internal audits and external compliance reporting workflows.


