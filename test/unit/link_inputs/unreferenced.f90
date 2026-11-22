! nothing calls this by a strong reference; weak_probe.c only refers to it weakly
function unreferenced_fn() bind(C, name="unreferenced_fn") result(r)
  use iso_c_binding
  implicit none
  integer(c_int) :: r
  r = 7
end function unreferenced_fn
