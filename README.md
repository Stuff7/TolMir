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

### 2. Set Load Order

Edit the `loadorder` file to define the order in which your mods should load. Use the mod filenames **without extensions**.

Mods are **enabled** by prepending them with a `*`, like so:

```
*mod1
*mod2
mod3  # not enabled
```

Only enabled mods will be linked and included in the mounted overlay.

---

### 3. Install Mods

Installs enabled mods by symlinking them from `inflated/` to `installs/`. If a mod includes a FOMOD installer, you'll be prompted for input.

```sh
tolmir install
```

---

### 4. Mount Mods

Generates `mount.sh` to overlay the mods onto your Skyrim directory according to the load order. Also creates `unmount.sh` to undo the mount cleanly.

```sh
tolmir mount
```
