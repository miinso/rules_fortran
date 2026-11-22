! initializes a COMMON block and defines nothing a program would call.
! gnu ld pulls such a unit out of an archive by itself, not every linker does
block data cfg_init
  implicit none
  integer :: x
  common /cfg/ x
  data x /42/
end block data cfg_init
