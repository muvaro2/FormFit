# FormFit Watch (Core Motion Prototype)

watchOS app to capture motion on-device:
- adjustable tick (10–200 ms)
- rolling buffer (~5k rows)
- CSV export to Documents

> Simulator won’t produce real sensor values. Test on a real watch.

## Build
Open `watchos/FormFitWatch/FormFitWatch.xcodeproj` in Xcode, select a Watch simulator, Run.

## Usage
- Start / Stop / Clear controls.
- Adjust **Tick** (ms); applies live while running.
- **Save CSV** writes `Documents/formfit-<timestamp>-<tick>ms.csv`.

## Next
- Real-device run (grant Motion permission)
- WatchConnectivity: transfer CSV to iPhone
- Feature extraction + ML pipeline
