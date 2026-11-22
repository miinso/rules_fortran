program main
  use solver
  implicit none
  if (solve() /= 8) error stop 1
end program main
