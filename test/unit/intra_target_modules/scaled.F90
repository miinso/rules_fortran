! preprocessed, and uses a sibling module
module scaled
  use types
  implicit none
#ifdef SCALE
  integer, parameter :: scaled_base = base * SCALE
#else
  integer, parameter :: scaled_base = -1
#endif
end module scaled
