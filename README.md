# Viska

Lokal röstdiktering på svenska för macOS, likt Wispr Flow. Håll **höger ⌘**,
prata och släpp. Talet blir text på din egen dator med KB-Whisper från KBLab,
och texten klistras in där markören står. Inget ljud lämnar datorn.

Appen ligger i menyraden som ett **V**. Grönt betyder redo, rött att den
spelar in, orange att den skriver ut och grått att talmodellen laddas.

## Installera (en gång)

```bash
cd ~/code/viska-app
./setup.sh        # bygger whisper.cpp (whisper-server och whisper-cli)
./build_app.sh    # bygger Viska.app
```

Ingen Homebrew krävs. Första gången appen startar laddar den ner talmodellen
och visar hur långt den har kommit.

## Starta

```bash
open ~/code/viska-app/Viska.app
```

### Behörigheter (första gången)

macOS frågar om två saker för **Viska**. Godkänn båda i
Systeminställningar → Integritet och säkerhet:

- **Mikrofon** för att spela in.
- **Tillgänglighet** för att fånga snabbtangenten och klistra in (⌘V).

Snabbtangenten slås på av sig själv när Tillgänglighet är godkänd.

## Använda

- **Talmodell** i menyn:
  - **Snabb** (KB-Whisper small, 175 MB). Cirka 0,4 s per mening på en M2.
  - **Noggrann** (KB-Whisper medium, 540 MB). Cirka 1,1 s per mening.

  Byter du till en modell som saknas laddas den ner först.
- **Språk** i menyn: svenska är standard.
- **Omskrivning** i menyn gör rörigt tal till färdig text med en lokal
  språkmodell i [Ollama](https://ollama.com). Den tar bort "eh", "typ" och
  "liksom" och rättar meningar och skiljetecken. Standardmodellen är
  `qwen2.5:7b` (cirka 2 s per mening på en M2). Hämta den en gång med
  `/Applications/Ollama.app/Contents/Resources/ollama pull qwen2.5:7b`.
  - **Redigera prompt…** öppnar `prompter/omskrivning.md`, där reglerna för
    modellen står. Ändringen gäller från nästa diktering.
  - Om Ollama inte svarar, eller om modellen verkar hitta på, klistras din
    råa text in i stället. Sådana fall sparas i `loggar/omskrivning-fel.log`.
- **Tid** i menyn visar hur lång tid det tog från att du släppte ⌘ tills
  texten klistrades in. Klicka för att öppna hela tidsloggen.

## Så funkar det

- `app/ui/` är gränssnittet: menyraden, snabbtangenten (CGEventTap på höger ⌘),
  inspelningen (16 kHz mono), rutan med vågform och nedladdningsfönstret.
- `app/core/` är logiken utan gränssnitt, så att den går att testa:
  - `WhisperServer.swift` håller `whisper-server` igång i bakgrunden med
    modellen laddad. Den lyssnar bara på 127.0.0.1. Varje diktering skickas
    dit, så modellen behöver inte läsas in på nytt varje gång.
  - `Models.swift` beskriver modellerna och laddar ner dem från Hugging Face.
  - `Latency.swift` mäter tiden per steg.

Viskas filer ligger i `~/Library/Application Support/Viska/`:

- `models/` innehåller talmodellerna.
- `loggar/tider.tsv` har en rad per diktering med tid per steg.
- `loggar/whisper-server.log` är talmotorns logg.

## Test

```bash
./tests/run.sh                                   # enhetstester
./tests/run.sh bench <modell.bin> <fil.wav>…     # mäter riktig transkribering
```

Testljud kan du göra med Macens svenska röst:
`say -v Alva -o t.wav --data-format=LEI16@16000 "Eh, hej, typ."`

## Terminalläge (utan app)

`./run.sh` startar ett äldre, enklare läge i Python. Det använder fortfarande
OpenAIs Whisper-modeller i `models/` och kräver `pynput`.

## Felsökning

- **V:et syns men snabbtangenten gör inget.** Tillgänglighet saknas. Ge den
  till Viska. Efter en ny byggning kan macOS kräva att du tar bort Viska ur
  listan och lägger till den igen.
- **V:et är grått länge.** Talmotorn startade inte. Läs
  `loggar/whisper-server.log`.
- **"saknar whisper-server" i menyn.** Kör `./setup.sh`.
