      module nekmpi
#ifdef MPI
      integer nid_mpi
#else
      integer nid_serial
#endif
      end module
