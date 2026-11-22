! its own .mod file refers to vendor.mod, so whoever uses this module needs both
module wrapper
  use vendor
  implicit none
contains
  integer function wrapped()
    wrapped = vendor_value() + 1
  end function wrapped
end module wrapper
