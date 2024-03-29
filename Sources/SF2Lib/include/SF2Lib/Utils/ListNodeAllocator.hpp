#pragma once

#include <cstddef>
#include <memory>
#include <limits>

namespace SF2::Utils {

/**
 Custom allocator for std::list nodes. We allocate all nodes that we will ever need and then keep them when list
 deallocates them. This is so that we do not incur any memory allocations when voices change while we are rendering.
 */
template <typename T>
class ListNodeAllocator {
public:
  using value_type = T;

  /**
   Construct a new allocator that will keep around maxNodeCount nodes.

   @param maxNodeCount max number of list nodes
   */
  explicit ListNodeAllocator(size_t maxNodeCount) noexcept : maxNodeCount_{maxNodeCount} {}

  /**
   Template conversion constructor for U->T. Just copy the configuration parameter and move on.
   */
  template <typename U> ListNodeAllocator(const ListNodeAllocator<U>& rhs) noexcept : maxNodeCount_{rhs.maxNodeCount()}
  {}

  /**
   Move constructor. Just copy the configuration parameter.
   */
  ListNodeAllocator(ListNodeAllocator&& other) noexcept
  : maxNodeCount_{other.maxNodeCount_}
  {}

  /**
   Destructor. Release any allocated nodes.
   */
  ~ListNodeAllocator() noexcept
  {
    if (memoryBlock_ != nullptr) ::free(memoryBlock_);
    memoryBlock_ = nullptr;
  }

  ListNodeAllocator(const ListNodeAllocator&) = delete;
  ListNodeAllocator& operator =(const ListNodeAllocator&) = delete;
  ListNodeAllocator& operator =(ListNodeAllocator&& other) noexcept = delete;

  union Node {
    Node* next;
    typename std::aligned_storage_t<sizeof(T), alignof(T)> storage;
  };

  /**
   Allocate a new node.
   */
  [[nodiscard]] value_type* allocate(std::size_t)
  {
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
  void deallocate(value_type* p, std::size_t) noexcept
  {
    auto ptr = reinterpret_cast<Node*>(p);
    ptr->next = freeList_;
    freeList_ = ptr;
  }

  size_t maxNodeCount() const noexcept { return maxNodeCount_; }

private:
  size_t maxNodeCount_;
  Node* freeList_{nullptr};
  void* memoryBlock_{nullptr};
};

template <typename T, typename U>
inline bool operator == (const ListNodeAllocator<T>&, const ListNodeAllocator<U>&) noexcept {
  return true;
}

template <typename T, typename U>
inline bool operator != (const ListNodeAllocator<T>&, const ListNodeAllocator<U>&) noexcept {
  return false;
}

}
