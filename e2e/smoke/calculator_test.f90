program calculator_test
  use calculator, only: answer
  implicit none

  if (answer() /= 42) then
    write (*, *) "FAIL: expected 42, got", answer()
    stop 1
  end if
end program calculator_test
