# snapshot-text-audit

Finds text that is **cut off**, **sliced by a frame edge**, or **left untranslated** in snapshot-test
reference images.

A snapshot test asserts *"this still looks like it did"*. It cannot notice that what it captured was
broken to begin with — a reference recorded with a truncated button label passes forever. This reads
the images instead, with Apple's Vision framework, and says what is wrong with them.

Built against a real iOS corpus of 967 references across 6 languages, where it found truncated
confirm/cancel buttons that were indistinguishable from each other, a primary call-to-action sliced by
the frame, and four separate strings shipping in English on translated screens.

## Install

With [mise](https://mise.jdx.dev) — nothing to install, nothing to compile:

```sh
mise use -g github:bonkey/snapshot-text-audit
```

Or run it once without installing anything at all:

```sh
mise x github:bonkey/snapshot-text-audit -- snapshot-text-audit path/to/__Snapshots__
```

Pin it per project in `.mise.toml`, so everyone on the repo gets the same version:

```toml
[tools]
"github:bonkey/snapshot-text-audit" = "latest"
```

<details>
<summary>Other ways in</summary>

**Download the binary** — one universal build, Apple silicon and Intel:

```sh
gh release download --repo bonkey/snapshot-text-audit --pattern '*.tar.gz' -O - | tar xz
```

Or take the tarball from the [Releases page](https://github.com/bonkey/snapshot-text-audit/releases);
`checksums.txt` is attached to every release.

**Build from source:**

```sh
git clone https://github.com/bonkey/snapshot-text-audit
cd snapshot-text-audit
just install                  # universal binary → ~/.local/bin
PREFIX=/usr/local/bin just install
```

Without `just`: `swift build -c release && cp .build/release/snapshot-text-audit ~/.local/bin/`

</details>

Requires macOS 13+. No dependencies.

## Use

```sh
# everything under a directory
snapshot-text-audit path/to/__Snapshots__

# only what changed — the usual CI shape
snapshot-text-audit path/to/__Snapshots__ --changed origin/main

# narrow it down
snapshot-text-audit . --include 'FocusWidget*' --exclude '*-dark.png'

# draw the offending image right in the terminal (iTerm2)
snapshot-text-audit . --images
snapshot-text-audit . --zoom 2              # twice as big
snapshot-text-audit . --image-size 900x1400 # explicit fit box
```

`--zoom` and `--image-size` both imply `--images`. Images are fitted inside a box rather than sized by
width alone: snapshot corpora mix near-square widget tiles with phone screens three times taller than
they are wide, and sizing those by width buries the terminal in scrollback. The default box is
400×700; `--zoom 2` makes it 800×1400.

Exit code is `1` when there are findings, `0` when clean, `2` on bad usage — so it drops into a
pipeline unchanged.

## What it checks

### Truncated text — reliable

Text cut short with an ellipsis. A letter or digit must sit immediately before the dots, which is what
separates a real truncation from a decorative `···` overflow-menu glyph. On the corpus this was built
against, that one rule removed 59% of raw hits with no judgement call, leaving roughly 96% precision.

**Good enough to fail a build.**

### Untranslated text — reliable, but needs calibrating once

Compares every translated render against the same render in the baseline language. A sentence that is
character-for-character identical on a screen that should be translated is a missing catalog entry —
invisible to catalog tooling, because the key exists and the wrong text ships.

It cannot know that a domain list, a person's name or deliberately-verbatim copy is *supposed* to be
identical. Accept those once into a baseline and the check goes quiet. Expect a few dozen entries the
first time; on the reference corpus, 802 raw findings collapsed to 176 unique records.

**Good enough to fail a build, after the first calibration pass.**

### Edge-clipped text — informational only, off by default

Text running into a frame edge, which *might* mean it is sliced. Enable with `--edges`.

A bounding box near an edge is indistinguishable from text that simply ends there, so this is wrong
far more often than it is right — around nine in ten hits on the reference corpus were harmless. One
filter is applied because it was verified to help: a cut appearing in *every* language is structural
(a scroll fold, a pinned footer), while a real overflow spares the baseline language, so groups that
fire in every language are dropped.

Never affects the exit code. It exists because it is the only way to catch clipping that produces no
ellipsis — including the two worst defects found on the corpus it was built against.

## Baselines

```sh
snapshot-text-audit . --write-baseline > snapshot-text-baseline.txt
snapshot-text-audit . --baseline snapshot-text-baseline.txt
```

Records are `suite | test | geometry | language | kind | text | reason`. **Every field except `kind`
is a glob**, so a record is as tight or as broad as its reason deserves:

```
# this exact string, everywhere it appears
GardienComposerSnapshotTests | composer-disabled-send-button | * | * | truncated | Ask to unblock... | placeholder, by design

# a whole class — titles in a glanceable widget are meant to ellipsise
CalendarWidgetSnapshotTests | meeting-focus* | * | * | truncated | * | event titles ellipsise by design
```

Globbing `text` is the durable choice — it survives fixture copy changing — but it will also swallow a
*new* truncation in that test. Spell the text out when the specific string is what makes it
acceptable. `kind` is never globbed, so accepting a truncation never quietly accepts a missing
translation.

**The key deliberately excludes the file name.** Snapshot references get renamed wholesale — trait
segments added, tests renamed — without a single pixel changing. A file-name key would go stale on
such a commit and report every accepted finding as new. The recognised `text` *is* part of the key, in
the other direction: if a translation changes, the finding correctly comes back for review.

## Names it understands

```
<test>.<geometry>-<trait>-<language>-<appearance>.png

confirm-timed-block.148x148-small-min-default-pt-PT-light.png
guardians-step.iPhone17-default-xLarge-fr-light.png
```

Segments are peeled off the tail, so unknown or missing ones degrade to `geometry` rather than
failing. Languages parse as `en`, `pt-BR`, `es-419`.

## Performance

Roughly 60s for 1000 images, about 1s for a handful — and a handful is the normal case when scoped
with `--changed`.

Vision serialises inside a single process; running several processes in parallel is about three times
faster than threads within one. If whole-corpus runs become a bottleneck, sharding across processes is
the lever.

## Tests

```sh
swift test
```

Covers file-name parsing, the truncation rule, baseline matching (including that a rename does not
resurrect an accepted finding, and that changed copy does), glob filters, and image-box scaling.

## Limits

It reads pixels, so it only knows what a camera would know.

- Cannot see text overlapping other text
- Cannot see text spilling out of a control away from a frame edge
- Says nothing about colour, contrast, spacing or alignment
- Judges whether text *fits*, never whether it is *correct*

On the corpus this was built against, three conclusions drawn from raw output were reversed by opening
the actual image: an intentional placeholder, a set of decorative `···` menus, and a footer overlap
that turned out to be a deliberate assertion in another test. Treat findings as candidates.

## Releasing

Cut from a laptop; there is no CI.

```sh
just release v1.0.0
```

Runs the tests, refuses a dirty tree or a tag that already exists, tags and pushes, builds one binary
carrying both architectures, and publishes a GitHub release with the tarball and its checksum attached
— so anyone can download and run it without a Swift toolchain.

`just package` stops short of publishing if you only want the artefact locally.

## Licence

MIT
