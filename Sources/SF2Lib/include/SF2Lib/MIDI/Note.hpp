// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <string>
#include <array>

namespace SF2::MIDI {

/**
 A MIDI note representation. MIDI note values range from 0 to 255, and so does this.
 */
class Note {
public:
  inline static const int Min = 0;
  inline static const int Max = 127;

  /**
   Construct new note.

   @param value the MIDI value to represent
   */
  explicit Note(int value) noexcept : value_{value}, note_{size_t(value % 12)} {}

  /// @returns the octave that the note resides in
  int octave() const noexcept { return value_ / 12 - 1; }

  /// @returns true if the note is accented (sharp / flat)
  bool accented() const noexcept { return (note_ < 5 && (note_ & 1) == 1) || (note_ > 5 && (note_ & 1) == 0); }

  /// @returns textual representation of the note (shows a sharp for accented notes)
  std::string label() const noexcept {
    return labels_[note_] + std::to_string(octave()) + (accented() ? sharpTag_ : "");
  }

  /// @returns the MIDI value for the note
  int value() const noexcept { return value_; }

  friend std::strong_ordering operator <=>(const Note& lhs, const Note& rhs) { return lhs.value_ <=> rhs.value_; }

  operator int() const noexcept { return value(); }

private:
  inline static std::string const sharpTag_ = "♯";
  inline static std::array<std::string, 12> const labels_ = {
    "C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"
  };

  int value_;
  size_t note_;
};

} // namespace SF2::MIDI
