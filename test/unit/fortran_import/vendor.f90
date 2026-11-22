! stands in for a library built outside of bazel: the tests only ever get
! its .mod file and its archive, never this source
module vendor
  implicit none
contains
  integer function vendor_value()
    vendor_value = 42
  end function vendor_value
end module vendor
