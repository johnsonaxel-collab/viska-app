# Viska

Egen, lokal röstdiktering för macOS — likt Wispr Flow. Håll **höger ⌘**, prata,
släpp. Talet transkriberas lokalt med `whisper.cpp` (ingen data lämnar datorn)
och klistras in där markören står.

Levereras som en riktig menyrads-app: **`Viska.app`** (ikon 🎙 uppe till
höger). Skriven i Swift — inga Python-beroenden i själva appen.

## Installera (en gång)

```bash
cd ~/whisperflow
./setup.sh        # bygger whisper.cpp + laddar ner modellen (om ej redan gjort)
./build_app.sh    # bygger Viska.app
```

Ingen Homebrew krävs.

## Starta

```bash
open ~/whisperflow/Viska.app     # eller dubbelklicka i Finder
```

Ikonen 🎙 dyker upp i menyraden. Håll **höger ⌘**, prata, släpp → texten
klistras in. Ikonen visar läget: 🎙 redo · 🔴 spelar in · ⏳ transkriberar.

### Behörigheter (första gången)

macOS frågar om två saker för **Viska** — godkänn båda i
Systeminställningar → Integritet och säkerhet:

- **Mikrofon** — för att spela in
- **Tillgänglighet** — för att fånga snabbtangenten och klistra in (⌘V)

Efter att du gett Tillgänglighet: **avsluta och öppna appen igen** (menyn →
Avsluta, sedan `open`). Snabbtangenten aktiveras först när behörigheten finns.

## Använda

- **Språk** — via menyn: Auto / Svenska / English (sparas mellan körningar).
- **Avsluta** — via menyn, eller ⌘Q när menyn är öppen.

Bättre svenska (större modell, långsammare): hämta `medium` en gång och peka om:

```bash
WF_MODEL=ggml-medium.bin ./fetch_model.sh
```
Byt sedan modell i menyn är inte implementerat — sätt standard genom att köra:
```bash
defaults write com.axel.viska model ggml-medium.bin
```
och starta om appen. (Återställ med `defaults delete com.axel.viska model`.)

## Så funkar det

- `app/Viska.swift` → hela appen: menyrad (NSStatusItem), global
  snabbtangent (CGEventTap på höger ⌘), inspelning (AVAudioRecorder, 16 kHz
  mono), transkribering via `whisper-cli`, inklistring (NSPasteboard + ⌘V).
- `whisper.cpp/build/bin/whisper-cli` → lokal transkription (byggd med Metal).
- `models/ggml-small.bin` → modellen.

Appen letar upp `whisper.cpp` och `models/` relativt sin egen plats, så **låt
`Viska.app` ligga kvar i `~/whisperflow/`** (eller kör om `build_app.sh`
om du flyttar mappen).

## Terminal-alternativ (utan app)

Det finns även ett enklare CLI-läge om du hellre kör i terminalen. Det kräver
`pynput` (`python3 -m pip install --user pynput`) och att **Terminal** har
Mikrofon + Tillgänglighet:

```bash
./run.sh                 # eller: WF_LANG=sv ./run.sh
```

## Felsökning

- **Ikonen syns men snabbtangenten gör inget** → Tillgänglighet saknas; ge den
  till Viska och starta om appen.
- **Ingen inspelning / tyst** → Mikrofon-behörighet saknas, eller för kort tryck.
- **Fel språk** → välj språk i menyn.
- **"saknar: …" i menyn** → kör `./setup.sh` (bygger whisper-cli + hämtar modell).
