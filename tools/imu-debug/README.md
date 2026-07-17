# Voxa IMU Lab dashboard

This diagnostic connects directly to the standalone Nano firmware in
`firmware/imu-diagnostic`. It is deliberately separate from the iOS app and the
production haptic protocol.

## Run it

1. Wire the IMU to `3V3`, `GND`, `A4/SDA`, and `A5/SCL`.
2. Build and flash the diagnostic firmware using its README.
3. Start the dashboard:

   ```sh
   tools/imu-debug/serve.sh
   ```

4. In the Chrome page, select **Connect IMU**, then choose **Voxa IMU Lab**.
5. Move the sensor as though it were on the presenting wrist. The two plots show
   X/Y/Z acceleration and angular velocity; **Export CSV** saves the most recent
   15 seconds.

Desktop Chrome is required. Web Bluetooth is unavailable in Safari and iPhone
browsers.

## What the movement rating means

The rating is a heuristic, not a trained model. Every 40 ms sample contributes
to a rolling four-second window:

1. `dynamic acceleration = abs(length(accel XYZ) - 1 g)` removes gravity while
   remaining independent of wrist orientation.
2. RMS dynamic acceleration represents translation or sharp hand movement.
3. RMS angular velocity represents wrist turns and sweeping gestures.
4. Active time is the fraction of samples above `0.08 g` or `35 °/s`.
5. The 0–100 score is `40% acceleration + 40% gyro + 20% active time`, normalized
   at `0.35 g`, `160 °/s`, and `55% active time`.

Initial thresholds:

| Score | Classification | Interpretation |
| --- | --- | --- |
| `< 22` | Too little | Wrist is mostly stationary across the window |
| `22–62` | Right amount | Regular, controlled emphasis gestures |
| `> 62` | Too much | Large or nearly continuous movement |

The two score boundaries are editable in the page. They are prototype defaults,
not population-validated cutoffs. Collect labeled presentation clips and tune
them before using the classifier as a product claim. The exact implementation
and behavior tests live in `motion-classifier.mjs` and
`motion-classifier.test.mjs`.

## Test the browser-side logic

```sh
node --test tools/imu-debug/*.test.mjs
```
