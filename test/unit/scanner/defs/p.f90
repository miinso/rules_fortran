program p
  use nekmpi
  nid_mpi = 1
  if (nid_mpi /= 1) error stop 1
end program p
