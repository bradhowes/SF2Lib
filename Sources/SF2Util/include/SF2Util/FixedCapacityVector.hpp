// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <cstddef>
#include <new>
#include <stdexcept>
#include <type_traits>
#include <utility>

namespace SF2::Utils {

/**
 A vector-like container with storage for a fixed number of elements held inline, so it never allocates. Suitable for
 use on the render thread. Elements are constructed in place, so `T` does not need to be default-constructible or
 assignable (e.g. `Voice::State::Config`, which holds references).

 @arg T the element type
 @arg Capacity the maximum number of elements
 */
template <typename T, size_t Capacity>
class FixedCapacityVector {
public:
  using value_type = T;
  using iterator = T*;
  using const_iterator = const T*;

  FixedCapacityVector() noexcept = default;

  FixedCapacityVector(const FixedCapacityVector& rhs) noexcept(std::is_nothrow_copy_constructible_v<T>) {
    for (const auto& value : rhs) emplace_back(value);
  }

  FixedCapacityVector(FixedCapacityVector&& rhs) noexcept(std::is_nothrow_move_constructible_v<T>) {
    for (auto& value : rhs) emplace_back(std::move(value));
    rhs.clear();
  }

  FixedCapacityVector& operator=(const FixedCapacityVector&) = delete;
  FixedCapacityVector& operator=(FixedCapacityVector&&) = delete;

  ~FixedCapacityVector() noexcept { clear(); }

  /**
   Construct a new element at the end of the container.

   @param args the arguments to pass to the constructor of `T`
   @returns true if added, false if the container was already full (nothing is constructed)
   */
  template <typename... Args>
  bool emplace_back(Args&&... args) noexcept(std::is_nothrow_constructible_v<T, Args...>) {
    if (size_ == Capacity) return false;
    ::new (static_cast<void*>(data() + size_)) T(std::forward<Args>(args)...);
    ++size_;
    return true;
  }

  /// Destroy all elements.
  void clear() noexcept {
    while (size_ > 0) data()[--size_].~T();
  }

  size_t size() const noexcept { return size_; }
  bool empty() const noexcept { return size_ == 0; }
  bool full() const noexcept { return size_ == Capacity; }
  static constexpr size_t capacity() noexcept { return Capacity; }

  T& operator[](size_t index) noexcept { return data()[index]; }
  const T& operator[](size_t index) const noexcept { return data()[index]; }

  /// Bounds-checked access. Throws std::out_of_range, so not for the render thread.
  const T& at(size_t index) const {
    if (index >= size_) throw std::out_of_range("FixedCapacityVector::at");
    return data()[index];
  }

  iterator begin() noexcept { return data(); }
  iterator end() noexcept { return data() + size_; }
  const_iterator begin() const noexcept { return data(); }
  const_iterator end() const noexcept { return data() + size_; }

private:
  T* data() noexcept { return std::launder(reinterpret_cast<T*>(storage_)); }
  const T* data() const noexcept { return std::launder(reinterpret_cast<const T*>(storage_)); }

  alignas(T) std::byte storage_[sizeof(T) * Capacity];
  size_t size_{0};
};

} // end namespace SF2::Utils
