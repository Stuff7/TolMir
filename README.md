# **TolMir**: Skyrim SE Mod Manager for Linux

## 🏔️ Efficient Mod Management for Skyrim Special Edition — Straight from Your Terminal

**TolMir** is a lightweight, terminal-based mod manager built specifically for **Skyrim Special Edition** on **Linux**. It helps you manage, organize, and load your mods quickly and reliably.

---

## 🚀 Usage

### 1. Set Paths

Configure the working directory for your mods and the root directory of your Skyrim installation:

```sh
tolmir set cwd /tolmir/working/directory
tolmir set gamedir /path/to/skyrim
```

---

### 2. Add Your Mods

Place your mod archives (ZIP, 7z, etc.) into the `mods/` folder inside your working directory:

```
/tolmir/working/directory/
└── mods/
    ├── mod1.7z
    ├── mod2.zip
    └── mod3.7z
```

TolMir will handle extraction and installation automatically.

---

### 3. Set Load Order

Edit the `loadorder` file to define the order in which your mods should load. Use the mod filenames **without extensions**.

Mods are **enabled** by prepending them with a `*`, like so:

```
*mod1
*mod2
mod3  # not enabled
```

Only enabled mods will be linked and included in the mounted overlay.

---

### 4. Install Mods

Installs enabled mods by symlinking them from `inflated/` to `installs/`. If a mod includes a FOMOD installer, you'll be prompted for input.

```sh
tolmir install
```

---

### 5. Mount Mods

Generates `mount.sh` to overlay the mods onto your Skyrim directory according to the load order. Also creates `unmount.sh` to undo the mount cleanly.

```sh
tolmir mount
```
