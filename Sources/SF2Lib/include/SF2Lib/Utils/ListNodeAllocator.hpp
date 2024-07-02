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
   @param count number of nodes to deallocate
   */
  void deallocate(value_type* p, std::size_t count) noexcept
  {
    assert(count == 1);
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

}
