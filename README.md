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

  * **v1.536 (Current)**
    * Automatic detection of CD, DVD, and Blu-ray optical drives has been added, completely eliminating the need to specify a drive letter; as soon as Windows detects the drive, the tool will identify it without any issues.
    * The disc detection system has been improved to operate automatically, without the need to press ENTER to continue.
    * The pulse system and other already-incorporated functions have been improved.
    * The remaining identified errors have been resolved.
    * This is the final version in the 1.xx branch before moving on to the 2.xx branch, which will arrive soon (once significant progress has been made on the third version of that branch).
  * **v1.467**
    * Excessive on-screen spam has been removed to provide a better experience when using the tool.
    * Some minor solutions
    * Code implemented by MartStartIV
  * **v1.457**
    * A disc detector has been added; this prevents the program from closing if the disc is missing and prompts you to insert one.
    * The log has been improved.
    * Some minor issues have been resolved.
    * Code implemented by MartStartIV
  * **v1.421**
    * A log tracking total weight limits has been added for users who wish to view the tool's activity history.
    * Pause and exit keys have been added to the interface and are displayed on-screen.
    * An issue causing a loop when activating the pause function has been resolved.
    * Minor fixes.
    * Code implemented by MartStartIV
  * **v1.399**
    * Pulse skipping precision has just been improved; testing shows virtually no video stuttering when using the supported PC emulators (PS1, PS2, PS3), while maintaining a steady data read rate.
    * System stability has been further improved.
    * Code implemented by MartStartIV
  * **v1.398**
    * The tool can now ignore pulses while reading real time data with its indicator.
    * The stability of the tool has been improved.
    * Code implemented by MartStartIV
  * **v1.305**
    * You can now switch to turbo mode without having to close the mini-program again.
    * You can activate or deactivate turbo mode instantly; the system will now emit a sound.
    * Code implemented by MartStartIV
  * **v1.102**
    * Added advanced support for specialized emulators (including RPCS3 adaptation).
  * **v1.101**
    * Compatibility with PPSSPP and improved stability were included.
</details>

### Notices

<details>
  <summary><strong>View project notices</strong></summary>
  <br>

  * **25-10-2026**
    * I am pleased to announce the launch of the new 2.xx branch, in which I aim to load a portion of data from optical discs (CD/DVD/Blu-ray) into RAM. The approach is dynamic grouping segments of the data and storing them as needed. If you are reading this, it means I have already made progress in the latest development version; I was quite excited to see that a small portion of the LBA (Logical Block Address) data was successfully stored in RAM (as confirmed by my tests). While it was only about 1–2 MB out of approximately 300 MB, it serves as a genuine starting point for this new approach—an improvement over my previous, less successful attempts. This will be available soon, as it is currently in the testing phase. I plan to release fully prepared versions, so I ask for your patience; it is a long and complex journey. However, if successful, this could potentially give this specific optical format a "second life." Stay tuned for further updates! :)
    * A new experimental feature has been introduced that handles the capture of LBA data from optical discs, while maintaining compatibility with pulse based signaling (including pulse skipping) to avoid performance issues. By integrating with .NET, this feature allows for better management and control of the optical drive. Look for further developments in upcoming stable releases—including this experimental mode and the forthcoming "experimental+" version (which will incorporate the features outlined in the 2.xx branch project). Stay tuned for future updates!
  * **15-10-2026**
    * For now, one more version from the 1.xx branch is set to be released very soon in addition to the one recently published and the reason for this will be explained in the next point.
    * In the second version of the 2.xx branch, the foundation has been laid for what could be described as the potential to eliminate disk latency. While this offers a promising path toward that goal, I will provide more details once the first version of the 2.xx branch which includes this experimental feature is released. I am currently still conducting tests on this second version of the 2.xx branch. The first version of the 2.xx branch will be available very soon, incorporating the full scope of what I have in mind; however, for practical reasons, it will be rolled out in stages. I am well aware that this will take time and that the implementation must be nearly perfect to achieve the desired performance. Consequently, the 2.xx branch may go through several iterations before the final objective is met. Looking ahead, if everything goes according to plan, the future 3.xx branch will focus on further optimizing what has been achieved provided, of course, that everything works out as intended! :)
  * **13-10-2026**
    * I would like to inform you that further versions within the 1.xx branch will be released, improving necessary functions for greater stability and adding additional features.
    * I have just started developing the 2.xx branch, aiming to take the tool to the next level and resolve an issue that affects the overall experience when reading data from a disk. When this development version is released, the new functionality will be in experimental mode so I can test what I intend to implement. It is quite a complex undertaking especially since I want to stick to PowerShell, which is the core objective so it will take some time if everything goes according to plan.
  
</details>
