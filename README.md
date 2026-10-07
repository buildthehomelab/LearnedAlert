# LearnedAlert

A World of Warcraft **3.3.5a (Wrath of the Lich King)** addon that shows a loot-style toast for every spell, ability, or passive you learn. It's built for servers that teach spells automatically on level up.

It uses the "You have learned a new spell/ability/passive effect" system messages, so it works whether the server sends spell links or plain text like `Frost Nova (Rank 1)`.

## Features

- One toast per learned spell, with its icon, name, and rank
- Hover for the spell tooltip, shift-click to link it in chat, right-click to dismiss
- Up to 4 toasts on screen at once (configurable); extras queue
- One sound per level-up batch, not one per toast
- Skips the duplicate spell messages the game sends after a loading screen or a dual-spec swap

## Upgrading from pretty_levelup

This addon used to be called pretty_levelup. Delete the old `Interface/AddOns/pretty_levelup` folder
when you install LearnedAlert, or both will show a toast for every spell.

## Requirements

- A WoW 3.3.5a (12340) client. The addon runs entirely in the client. It reads the "You have learned..." system messages, so it works on [AzerothCore](https://www.azerothcore.org) and any other 3.3.5a server that sends them.

## Installation

1. Download this repo (Code → Download ZIP) and extract it.
2. Copy the inner `LearnedAlert` folder into your `Interface/AddOns` folder (`World of Warcraft/Interface/AddOns/`), so you end up with `Interface/AddOns/LearnedAlert/LearnedAlert.toc`.
3. Restart the game.

## Usage

- `/learned test`: show a sample toast (`/levelup test` still works too)

## Configuration

Edit `LearnedAlert/config.lua`:

| Option | Default | Description |
| --- | --- | --- |
| `scale` | `1` | Toast size |
| `sound` | `true` | Play a sound |
| `sound_file` | `"levelup.mp3"` | Sound file in `LearnedAlert/assets/` (.mp3, .ogg, .wav) |
| `numbuttons` | `4` | Toasts shown at once (max 8) |
| `anims` | `true` | Glow and shine animations |
| `point_x`, `point_y` | `0`, `120` | Toast position |
| `spell_quality` | `4` | Border and name color (2 green, 3 blue, 4 purple, 5 orange, 7 gold) |

## Troubleshooting

- **Two toasts for every spell:** the old `Interface/AddOns/pretty_levelup` folder is still installed. Delete it.
- **No toast right after a loading screen or a spec swap:** that is deliberate. The game re-announces known spells then, so the addon ignores spell messages for about 5 seconds.
- **Checking it works:** `/learned test` shows a sample toast for a spell you know.

## Credits

- Based on [pretty_lootalert](https://github.com/s0h2x/pretty_lootalert) by s0h2x.
- Sound: "Arcade UI 1" by floraphonic, from [Pixabay](https://pixabay.com/).

Author: [buildthehomelab](https://github.com/buildthehomelab)

## License

No license is set. LearnedAlert is based on [pretty_lootalert](https://github.com/s0h2x/pretty_lootalert) by s0h2x, which is published without a license, so its author keeps their rights to that code. No license is added here until that changes.
