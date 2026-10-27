# Low-Poly Tile City

A cozy, procedural low-poly town that runs in the browser, built with Flutter (web).

![screenshot](docs/screenshot.png)

## Features

- **Procedural city** on a tiled board: townhouses, cottages, apartment blocks, office
  towers, parks with ponds, a central plaza with a fountain, a fairground with a spinning
  Ferris wheel, carousel and circus tent, a farm with a windmill, a supermarket with
  parking, a hospital with a helipad, a sports field and a church.
- **Living streets**: cars follow lanes and turn at intersections, and people walk the
  sidewalks.
- **Atmosphere**: time-of-day light (dawn → golden hour → night, with lit windows and
  street-lamp glow), four seasons (spring blossoms, summer green, autumn colours, winter
  snow with bare trees), and real-time ground shadows.
- **Wind**: speed slider plus a draggable compass. Trees sway and leaves (or petals or
  snow) blow, fall and settle. **Gust** and **Leaf devil** (a whirlwind that crosses town
  and lifts fallen leaves) add bursts.
- **Monuments**: click any house and replace it with Tokyo Tower, Christ the Redeemer,
  Petronas Towers, Sagrada Familia, St Basil's Cathedral, Atomium, Gateway Arch,
  Stonehenge, a Dutch windmill or the Moai, with a build-up animation. **Original**
  restores the house.
- **Town tools**: width/depth of the map, traffic & people density, street-tree density,
  leaf amount/size, **Switch trees** (mixed / round / pine / chunky / poplar),
  **Move blocks** (tap two blocks to swap them), **Reset blocks**, **Reset houses**,
  **Whole map**, and **Tilt-shift** depth-of-field.
- **Sound & music**: procedural Web Audio ambience (wind, rustling leaves, birds,
  crickets at night, distant traffic, construction hammering) and a generative ambient
  soundtrack.

## Controls

| Action | Input |
| --- | --- |
| Orbit | drag |
| Pan | right-drag, shift-drag, or two-finger drag |
| Zoom | scroll wheel / pinch |
| Select a house | click it |

## Running

```bash
flutter run -d chrome          # development
flutter build web --release    # production build in build/web
```

Only the web platform is set up for now.

## Deployment (GitHub Pages)

`.github/workflows/deploy-pages.yml` runs `flutter analyze`, `flutter test` and a
release web build on every push and pull request. On pushes to `main`/`master` (or a
manual run) it publishes `build/web` to GitHub Pages at
`https://<owner>.github.io/<repo>/`. The base href is set from the repo name.

One-time setup: **Settings → Pages → Build and deployment → Source: GitHub Actions**.

## How it works

There is no 3D engine dependency. `lib/engine` contains a small software renderer:
meshes are built from low-poly primitives (`mesh.dart`), lit per triangle with a
sun/sky hemisphere model that also handles seasons, snow and night emissives
(`lighting.dart`), and drawn with the painter's algorithm (objects depth-sorted, parts of
complex monuments sorted, back faces culled), all batched into a few
`Canvas.drawVertices` calls (`renderer.dart`). Static ground geometry and shadows are
cached in a `Picture` while the camera is still. Tilt-shift is a masked blur of the
frame.

`lib/world` holds the procedural city (`city.dart`, `buildings.dart`,
`monuments.dart`, `props.dart`), the simulation of traffic, wind and particles
(`simulation.dart`) and the shared state (`world.dart`). `lib/ui` holds the Flutter
panels, and `lib/audio` holds the Web Audio engine.

```bash
flutter test   # simulation and rendering smoke tests
```

Fonts: Inter and JetBrains Mono (SIL Open Font License).
