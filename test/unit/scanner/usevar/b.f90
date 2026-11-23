module uzb
  integer :: use(2)
contains
  subroutine s(x)
    real :: x(3)
    integer, parameter :: uzk = 1
    use = [integer :: uzk, 2]
    use: do concurrent (integer :: uzk2 = 1:3)
      x(uzk2) = 0
    end do use
  end subroutine s
end module uzb
