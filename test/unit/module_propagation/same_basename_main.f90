program same_basename_main
    use util_a, only: value_a
    use util_b, only: value_b
    implicit none

    if (value_a + value_b /= 3) then
        write (*, *) "FAIL: expected 3, got", value_a + value_b
        stop 1
    end if
end program same_basename_main
