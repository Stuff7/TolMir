# **TolMir**: Skyrim SE Mod Manager for Linux

## 🏔️ Efficient Mod Management for Skyrim Special Edition — Straight from Your Terminal

**TolMir** is a lightweight, terminal-based mod manager built specifically for **Skyrim Special Edition** on **Linux**. It helps you manage, organize, and load your mods quickly and reliably.

---

## 🔧 Build

1. Build required static libraries:

```sh
vendor/build.sh
```

2. Compile the TolMir binary:

```sh
zig build
```

This will produce a `tolmir` executable in the `zig-out/bin` directory.

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

### 5. Generate Mount Scripts

Creates two scripts:

* `mount.sh`: mounts your modded loadout over the Skyrim directory using OverlayFS
* `unmount.sh`: cleanly unmounts the overlay when you're done

```sh
tolmir mount
```

---

### 6. Play the Game

Run the `mount.sh` script to apply your mods, then launch Skyrim as usual:

```sh
./mount.sh
```

When you're finished playing, run:

```sh
./unmount.sh
```

This restores your game directory to its unmodded state.
