program via_wrapper_main
  use wrapper
  implicit none
  if (wrapped() /= 43) error stop 1
end program via_wrapper_main
