! fails unless the alwayslink library holding unreferenced_fn was linked whole
program weak_probe_main
  use iso_c_binding
  implicit none
  interface
    function weak_probe() bind(C, name="weak_probe") result(r)
      import :: c_int
      integer(c_int) :: r
    end function weak_probe
  end interface
  if (weak_probe() /= 7) error stop 1
end program weak_probe_main
