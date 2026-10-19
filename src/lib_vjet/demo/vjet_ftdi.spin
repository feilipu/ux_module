'' (C)2026 feilipu.
'' Beam-chase triangles plus the ACIA cog and the FTDI cog.
'' The serial cog runs while the triangles run. Cog 0 does not pump the FIFOs.
#define SCENE_TRIANGLES 1
#define WITH_ACIA 1
#define WITH_FTDI 1
#include "head_slice.spin"
