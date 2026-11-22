! fails unless the BLOCK DATA unit that initializes /cfg/ was linked in
program block_data_main
  implicit none
  integer :: x
  common /cfg/ x
  if (x /= 42) error stop 1
end program block_data_main
