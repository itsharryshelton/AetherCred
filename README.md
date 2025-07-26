# AetherCred - Entra ID Security & MFA Posture Dashboard

AetherCred is a powerful PowerShell and HTML-based tool designed to provide a clear and actionable overview of your Microsoft Entra ID (formerly Azure AD) security posture. It gathers detailed information about users, their MFA status, roles, and other security-related attributes, then presents it in an intuitive, searchable, and exportable web dashboard.

This tool allows for quick and easy report generating that can be easily shared to non-technical customers to help them better understand their Security Posture within their Entra estate.

<img width="1589" height="697" alt="chrome_44UppT86vK" src="https://github.com/user-attachments/assets/166b4a81-e82f-4b7d-8f32-e7258468e3f6" />




---

## Key Features

- **Comprehensive User Analysis:** Gathers data on all users, including their enabled status, creation date, last sign-in, and password policies.
- **Detailed MFA Reporting:** Differentiates between Modern MFA (Passwordless, Authenticator App, FIDO2) and Legacy MFA (SMS, Voice, TOTP), providing a clear view of your MFA landscape.
- **Security Scoring:** Assigns each user a security score from 0-100 based on critical risk factors like MFA enablement, password expiry policies, and privileged access.
- **Risk Flagging:** Automatically flags potential security risks such as "MFA Not Registered," "Password Expiry Enabled," and "Never Signed In."
- **Privileged Role Identification:** Highlights users with high-impact administrative roles (e.g., Global Administrator, Security Administrator).
- **Interactive Web Dashboard:**
    - Clean, dark-mode interface.
    - At-a-glance summary cards for key metrics.
    - A searchable and sortable table of all user data.
- **Multiple Export Options:**
    - **PDF Report:** Generate a professionally branded PDF of the full user report, complete with your company logo, directly from the dashboard.
    - **CSV Export:** The script automatically generates a `AetherCred-Data.csv` file for easy analysis in Excel or other tools.

---

## Prerequisites

Before running the script, ensure you have the following:

1.  **PowerShell:** Version 5.1 or higher.
2.  **Microsoft Graph PowerShell SDK:** This is required to interact with Microsoft Entra ID. If you don't have it, install it by running the following command in PowerShell as an administrator:
    ```powershell
    Install-Module Microsoft.Graph -Scope AllUsers
    ```
3.  **Required Permissions:** The user running the script must have sufficient permissions to grant admin consent for the required Microsoft Graph API scopes. The script will prompt for consent on the first run. The required scopes are:
    - `Application.ReadWrite.All`
    - `Directory.Read.All`
    - `User.Read.All`
    - `UserAuthenticationMethod.Read.All`
    - `AuditLog.Read.All`
    - `Reports.Read.All`

---

## Setup & Usage

1.  **Download Files:** Place the following three files into the **same folder**:
    - `AetherCred.ps1` (The main PowerShell script)
    - `AetherCred-Dashboard.html` (The report dashboard)
    - `AetherCredLogoCloud.png` (The logo file for the Enterprise App)
    - `favicon.ico` (The logo file used for HTML Favicon)

2.  **Run the Script:**
    - Open a PowerShell terminal.
    - Navigate to the folder where you saved the files.
    - Execute the script:
      ```powershell
      .\AetherCred.ps1
      ```

3.  **Authenticate:** A Microsoft Graph sign-in window will appear. Sign in with an account that has the necessary permissions. You may be asked to consent to the required API permissions on behalf of your organization.

4.  **View the Report:** Once the script finishes, it will automatically generate `AetherCred-Data.js` and `AetherCred-Data.csv`, and then launch the `AetherCred-Dashboard.html` file in your default web browser.

---

## How It Works

The project is split into two main parts:

1.  **Data Collection (PowerShell):** The `AetherCred.ps1` script connects to the Microsoft Graph API to fetch all relevant data. It processes this information, calculates scores, and then exports the final dataset into two formats: a `.js` file for the web dashboard and a `.csv` file for external use.
2.  **Data Visualization (HTML/JavaScript):** The `AetherCred-Dashboard.html` file uses the generated `.js` file as its data source. It uses JavaScript to dynamically build the summary cards and the main data table, providing a rich, interactive user experience without needing a web server. The PDF export functionality is also handled client-side using the `jsPDF` library.

---

## About the PDF Export

The PDF export feature is handled entirely client-side within your browser, meaning **no** data is sent to an external server for processing. This is achieved using the popular `jsPDF` and `jspdf-autotable` JavaScript libraries, which are included in the HTML file.

<img width="1096" height="771" alt="image" src="https://github.com/user-attachments/assets/f1e624d8-e1cf-406e-a696-14571641649f" />

When you click the **Download PDF Report** button:
1. The script gathers the currently loaded user data from the `AetherCred-Data.js` file.
2. It dynamically generates a multi-page PDF document in landscape orientation for better readability.
3. The document is branded with the AetherCred logo (as configured in the HTML file via base64 encoded logo).
4. A clean, professional table of all users and their security attributes is created.
5. The final PDF includes a header with the report title and generation date, and a footer with page numbers.

This approach ensures both security and convenience, allowing you to create shareable, branded reports without any server-side dependencies or complex setup.

---

## Customization

### PowerShell Script (`AetherCred.ps1`)

You can easily customize the Application details by modifying the variables at the top of the script:

```powershell
# SCRIPT CONFIGURATION
$AppName = "AetherCred"
$LogoFileName = "AetherCredLogoCloud.png"
$HomePageURL = "[https://github.com/itsharryshelton](https://github.com/itsharryshelton)"
```

### Dashboard (`AetherCred-Dashboard.html`)

To ensure your logo appears correctly on the PDF exports, you must update the hidden `<img>` tag in the HTML file.

1.  Convert your desired logo image to a Base64 string. You can use a free online tool for this (e.g., search for "image to base64 converter").
2.  Open `AetherCred-Dashboard.html` in a text editor.
3.  Find the following line:
    ```html
    <img id="logo-for-pdf" src="" style="display:none;" alt="Company Logo for PDF" />
    ```
4.  Paste your Base64 string inside the `src=""` attribute.

---

## Roadmap

I have several ideas for future enhancements to make AetherCred even more valuable. Contributions and suggestions are always welcome!

-   **Enhanced Scoring System:**
    -   Introduce more granular scoring based on the *types* of MFA methods registered (e.g., FIDO2 is better than SMS).
    -   Factor in user sign-in risk levels from Entra ID Protection.
    -   Allow admins to easily customize the scoring weights in the PowerShell script.

-   **Historical Data & Trend Analysis:**
    -   Save historical report data (e.g., in a local SQLite database or JSON files).
    -   Add a "Trends" tab to the dashboard to visualize security posture improvements over time.

-   **Deeper Risk Analysis:**
    -   Integrate with Entra ID Protection to flag risky users or sign-ins.
    -   Check for users with stale sign-in dates who still have active, privileged roles.

-   **Improved Dashboard Interactivity:**
    -   Add advanced filtering options (e.g., filter by MFA type, role, or risk flag).
    -   Implement column sorting directly in the HTML table.

-   **Better Webpage Features:**
    -   Toggle between Light and Dark mode.
    -   Main Dashboard for further future tools...

---

## Credits

- **Author:** Harry Shelton
