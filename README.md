<div align="center">
  
  <h1>💿 Byte-Level Continuous Reading System</h1>
  <p><strong>Advanced optimization tool for optical drives and emulation performance.</strong></p>
</div>

<hr>

### 🚀 System Overview
This system, executed via **PowerShell**, keeps the optical drive spinning continuously until the user manually closes it. 

* **The Problem:** Standard optical drives suffer from a spin-up time delay that can otherwise exceed **three seconds** before the drive responds.
* **The Solution:** By maintaining active byte-level contact, this script facilitates **significantly faster access** to data stored on the discs and completely eliminates mechanical spin-up latency.

---

### ⚙️ Quick Start & Requirements

To ensure it works correctly, simply run the `.bat` file. This launches PowerShell within the CMD interface itself, avoiding the need to load the separate PowerShell user interface.

| Requirement | Description |
| :--- | :--- |
| **File Location** | Both the `.bat` and `.ps1` files **must be located together** in the same directory. |
| **Execution** | Run the `.bat` file directly (it handles the PowerShell environment automatically). |

---

### ⚠️ Disclaimer & Responsibility

<blockquote>
  <strong>Use this tool responsibly.</strong><br>
  I am not liable for any misuse that might cause damage to the unit. Although such damage is unlikely under normal hardware conditions, it is worth mentioning this point explicitly.
</blockquote>

---

### 🪵 Changelog

<details>
  <summary><strong>Click to expand version history</strong></summary>
  <br>
  
  * **v1.305 (Current)**
    * You can now switch to turbo mode without having to close the mini-program again.
    * You can activate or deactivate turbo mode instantly; the system will now emit a sound.
    * Code implemented by MartStartIV
  * **v1.102**
    * Added advanced support for specialized emulators (including RPCS3 adaptation).
  * **v1.101**
    * Compatibility with PPSSPP and improved stability were included.
</details>

