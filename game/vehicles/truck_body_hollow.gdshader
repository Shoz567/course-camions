shader_type spatial;
// les deux faces : l'interieur de la coque se voit par les trous
render_mode cull_disabled;

// Coque creuse des remorques (2026-10-07 : « que les remorques soient vides,
// des qu'elle s'abime on voit a l'interieur, ca fait des trous dans la
// coque ») : la carrosserie de truck_body.gdshaderinc, percee au coeur des
// cicatrices graves (HOLLOW).
#define HOLLOW
#include "res://vehicles/truck_body.gdshaderinc"
