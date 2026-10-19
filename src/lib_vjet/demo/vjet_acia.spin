'' (C)2026 feilipu.
'' Beam-chase triangles plus the ACIA cog.
'' Port 0x80. A 1 ms low on P5 restarts the 8085 so it polls during the picture.
#define SCENE_TRIANGLES 1
#define WITH_ACIA 1
#include "head_slice.spin"
