#include "SF2Lib/Entity/Preset.hpp"

#include "SF2PresetInfo.hpp"

SF2PresetInfo::SF2PresetInfo(const SF2::Entity::Preset& preset)
: name_{preset.name()}, bank_{preset.bank()}, program_{preset.program()}
{}
