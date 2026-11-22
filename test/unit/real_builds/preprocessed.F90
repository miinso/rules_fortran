program preprocessed
  implicit none
#ifdef EXPECTED_DEFINE
  continue
#else
  write (*, *) "FAIL: EXPECTED_DEFINE not set"
  stop 1
#endif
end program preprocessed
