# Theme Transition Modes

The transition engine computes 8 mathematical visual transition styles executed via GLSL fragment shader compositing on `WlrLayer.Background` (beneath running applications):

1. **`color-morph`**: Smooth color morphing across palette stops with perceptual luminance weighting.
2. **`aurora-flow`**: Multi-spectral undulating wave patterns inspired by geomagnetic polar auroras.
3. **`ink-spread`**: Viscous fluid diffusion simulating ink expanding through paper fibers.
4. **`prism-shift`**: Chromatic aberration and refractive spectral dispersion across color channels.
5. **`liquid-transform`**: Organic fluid displacement with surface tension ripples.
6. **`atmospheric-fade`**: Non-linear gamma-corrected perceptual fade across shadow, midtone, and highlight regions.
7. **`material-repaint`**: Directional brush wipe replicating high-speed physical repainting.
8. **`reality-shift`**: Digital glitch slice displacement with scanline phase modulation.
