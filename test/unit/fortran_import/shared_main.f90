program shared_main
  use iso_c_binding
  implicit none
  interface
    function vendor_shared_fn() bind(C, name="vendor_shared_fn") result(r)
      import :: c_int
      integer(c_int) :: r
    end function vendor_shared_fn
  end interface
  if (vendor_shared_fn() /= 9) error stop 1
end program shared_main
