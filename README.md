
---
# 🛠️ Tool Framework Template Repository

## 📌 Overview

This repository provides a standardized framework for building, installing, and managing tool modules with automated dependency handling and CI/CD integration.

It ensures consistent structure, version-based dependency fetch, and seamless installation/uninstallation across environments.
---

---

## 🎯 Objective

- Provide a reusable template for new tool repositories  
- Automate dependency cloning and installation via Gradle  
- Support version pinning (branch, tag, commit) and `latest` keyword for most recent fetch  
- Simplify uninstall workflows with reversible scripts  
- Enable composite builds for scaling across multiple tools  

---

## 📂 Repository Structure

This template follows a standardized structure:

```
tool-template/
│
├── build.gradle        → Gradle tasks (install, uninstall, build, deploy)
├── deps.gradle         → External dependencies (repo + version or 'latest')
├── settings.gradle     → Composite build inclusion for dependencies
│
├── src/                → Source code & scripts
│   ├── install.sh      → Installer script (system/user setup)
│   └── uninstall.sh    → Uninstaller script (reverse install steps)
│
└── README.md
```

---

## ⚙️ Dependency Management

Dependencies are declared in `deps.gradle`:

```groovy
ext.org = "bit-faas"

ext.deps = [
    [repo: "toolA", version: "v1.2.0"],   // tag
    [repo: "toolB", version: "main"],     // branch
    [repo: "toolC", version: "latest"]    // always fetch most recent
]
```

- Gradle clones each dependency into `build/deps/` and runs its `:install` task.  
- `latest` keyword ensures the most recent commit from the default branch is fetched.  

---

## 🛠️ Install & Uninstall Scripts

- **install.sh**: Contains system/user setup steps.  
  - Example: `sudo apt install -y openjdk-17-jre`  
  - Configures environment variables and starts services.  

- **uninstall.sh**: Reverses installation steps.  
  - Example: `sudo apt remove --purge -y openjdk-17-jre`  
  - Cleans environment variables and stops services.  

Gradle tasks wrap these scripts:

```bash
./gradlew install
./gradlew uninstall
```

---

## 🚀 Usage

1. Clone this template to create a new tool repository:  
   - GitHub → **Use this template** → New repository.  
2. Define dependencies in `deps.gradle`.  
3. Implement your tool logic in `src/`.  
4. Run:

```bash
./gradlew install
./gradlew build
./gradlew deploy
```

5. To remove:

```bash
./gradlew uninstall
```

---

## 📈 Benefits

- Consistent repo structure across all tools  
- Automated dependency fetch and install  
- Clear separation of system vs user-level steps  
- Easy scaling with composite builds  
- Ready for CI/CD pipelines and branch protection rules  
```

---

