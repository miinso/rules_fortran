module smb
  use sma
  integer :: i, j
contains
  subroutine s()
    i = 1;; j = 2
    i = 1; j = 2; use_count: do i = 1, 2; end do use_count
  end subroutine s
end module smb
