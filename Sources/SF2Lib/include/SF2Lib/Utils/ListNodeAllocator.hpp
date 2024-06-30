#pragma once

#include <cstddef>
#include <memory>
#include <limits>

namespace SF2::Utils {

/**
 Custom allocator for std::list nodes. We allocate all nodes that we will ever need and then keep them when list
 deallocates them. This is so that we do not incur any memory allocations when voices change while we are rendering.
 */
template <typename T, std::size_t MaxNodeCount>
class ListNodeAllocator {
public:
  using value_type = T;

  static inline constexpr std::size_t maxNodeCount = MaxNodeCount;

  template <class U>
  struct rebind
  {
    typedef ListNodeAllocator<U, MaxNodeCount> other;
  };

  union Node {
    Node* next;
    typename std::aligned_storage_t<sizeof(T), alignof(T)> storage;
  };

  /**
   Allocate a new node.
   */
  [[nodiscard]] value_type* allocate(std::size_t count)
  {
    assert(count == 1);

    // Allocate our nodes first time we are asked for one. This makes the first allocation the most costly, but we
    // assume that this is done at some time where this cost is not an issue. One can force the allocation at a certain
    // time by doing a std::list operation to trigger an allocation/deallocation at a time that is most appropriate.
    if (memoryBlock_ == nullptr) {
      size_t elementSize = sizeof(Node);
      size_t totalSize = elementSize * maxNodeCount_;

      memoryBlock_ = ::malloc(totalSize);
      if (memoryBlock_ ==  nullptr) throw std::bad_alloc();

      Node* ptr = reinterpret_cast<Node*>(memoryBlock_);
      for (size_t index = 0; index < maxNodeCount_; ++index) {
        ptr->next = freeList_;
        freeList_ = ptr;
        ++ptr;
      }
    }

    auto ptr = freeList_;
    if (ptr == nullptr) throw std::bad_alloc();
    freeList_ = ptr->next;
    return reinterpret_cast<T*>(ptr);
  }

  /**
   Deallocate a node.

   @param p pointer to node to deallocate.
   */
  void deallocate(value_type* p, std::size_t count) noexcept
  {
    auto ptr = reinterpret_cast<Node*>(p);
    ptr->next = freeList_;
    freeList_ = ptr;
  }

  bool operator==(const ListNodeAllocator& other) noexcept { return false; }
  bool operator!=(const ListNodeAllocator& other) noexcept { return !(*this == other); }

private:
  size_t maxNodeCount_{MaxNodeCount};
  Node* freeList_{nullptr};
  void* memoryBlock_{nullptr};
};

//template <typename T, typename U>
//inline bool operator == (const ListNodeAllocator<T>&, const ListNodeAllocator<U>&) noexcept {
//  return false;
//}
//
//template <typename T, typename U>
//inline bool operator != (const ListNodeAllocator<T>&, const ListNodeAllocator<U>&) noexcept {
//  return true;
//}

}

//
//template<typename T, size_t num_items>
//class MyAllocator
//{
//public:
//  using value_type = T;
//  using pointer = T*;
//  using const_pointer = const T*;
//  using void_pointer = std::nullptr_t;
//  using const_void_pointer = const std::nullptr_t;
//  using reference = T&;
//  using const_reference = const T&;
//  using size_type = std::size_t;
//  using difference_type = std::ptrdiff_t;
//
//  /* should copy assign the allocator when copy assigning container */
//  using propagate_on_container_copy_assignment = std::true_type;
//
//  /* should move assign the allocator when move assigning container */
//  using propagate_on_container_move_assignment = std::true_type;
//
//  /* should swap the allocator when swapping the container */
//  using propagate_on_container_swap = std::true_type;
//
//  /* two allocators does not always compare equal */
//  using is_always_equal = std::false_type;
//
//  MyAllocator() : m_index(0) {};
//  ~MyAllocator() noexcept = default;
//
//  template<typename U>
//  struct rebind {
//    using other = MyAllocator<U, num_items>;
//  };
//
//  [[nodiscard]] pointer allocate(size_type n) {
//    if (m_index+n >= num_items)
//      throw std::bad_alloc();
//
//    pointer ret = &m_buffer[m_index];
//    m_index += n;
//    return ret;
//
//  }
//
//  void deallocate(pointer p, size_type n) {
//    (void) p;
//    (void) n;
//    /* do nothing */
//  }
//
//  size_type max_size() {
//    return num_items;
//  }
//
//
//  bool operator==(const MyAllocator& other) noexcept {
//    /* storage allocated by one allocator cannot be freed by another */
//    return false;
//  }
//
//  bool operator!=(const MyAllocator& other) noexcept {
//    /* storage allocated by one allocator cannot be freed by another */
//    return !(*this == other);
//  }
//
//private:
//  value_type m_buffer[num_items];
//  size_t m_index;
//};
