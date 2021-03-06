!>\file GFS_radiation_surface.f90
!! This file contains calls to module_radiation_surface::setemis() to set up
!! surface emissivity for LW radiation and to module_radiation_surface::setalb()
!! to set up surface albedo for SW radiation.
      module GFS_radiation_surface

      use machine,                   only: kind_phys

      contains

!>\defgroup GFS_radiation_surface GFS radiation surface
!! @{
!> \section arg_table_GFS_radiation_surface_init Argument Table
!! \htmlinclude GFS_radiation_surface_init.html
!!
      subroutine GFS_radiation_surface_init (me, sfcalb, ialb, iems, errmsg, errflg)

      use physparam,                only: ialbflg, iemsflg
      use module_radiation_surface, only: NF_ALBD, sfc_init

      implicit none

      integer,                              intent(in)  :: me, ialb, iems
      real(kind=kind_phys), dimension(:,:), intent(in)  :: sfcalb
      character(len=*),                     intent(out) :: errmsg
      integer,                              intent(out) :: errflg

      ! Initialize CCPP error handling variables
      errmsg = ''
      errflg = 0

      ! Consistency check that the number of albedo components in array
      ! sfcalb matches the parameter NF_ALBD from radiation_surface.f
      if (size(sfcalb,dim=2)/=NF_ALBD) then
        errmsg = 'Error in GFS_radiation_surface_init: second' // &
                 ' dimension of array sfcalb does not match' //   &
                 ' parameter NF_ALBD in radiation_surface.f'
        errflg = 1
      end if

      ialbflg= ialb                     ! surface albedo control flag
      iemsflg= iems                     ! surface emissivity control flag

      if ( me == 0 ) then
        print *,'In GFS_radiation_surface_init, before calling sfc_init'
        print *,'ialb=',ialb,' iems=',iems
      end if

      ! Call surface initialization routine
      call sfc_init ( me, errmsg, errflg )

      end subroutine GFS_radiation_surface_init


!> \section arg_table_GFS_radiation_surface_run Argument Table
!! \htmlinclude GFS_radiation_surface_run.html
!!
      subroutine GFS_radiation_surface_run (                            &
        im, frac_grid, lslwr, lsswr, lsm, lsm_noahmp, lsm_ruc,          &
        vtype, xlat, xlon, slmsk, lndp_type, n_var_lndp, sfc_alb_pert,  &
        lndp_var_list, lndp_prt_list, landfrac, snowd, sncovr,          &
        sncovr_ice, fice, zorl, hprime, tsfg, tsfa, tisfc, coszen,      &
        min_seaice, min_lakeice, lakefrac,                              &
        alvsf, alnsf, alvwf, alnwf, facsf, facwf,                       &
        semis_lnd, semis_ice, snoalb,                                   &
        albdvis_lnd, albdnir_lnd, albivis_lnd, albinir_lnd,             &
        albdvis_ice, albdnir_ice, albivis_ice, albinir_ice,             &
        semisbase, semis, sfcalb, sfc_alb_dif, errmsg, errflg)

      use module_radiation_surface,  only: f_zero, f_one,  &
                                           epsln, NF_ALBD, &
                                           setemis, setalb

      implicit none

      integer,              intent(in) :: im
      logical,              intent(in) :: frac_grid, lslwr, lsswr
      integer,              intent(in) :: lsm, lsm_noahmp, lsm_ruc, lndp_type, n_var_lndp
      real(kind=kind_phys), intent(in) :: min_seaice, min_lakeice

      real(kind=kind_phys), dimension(:),   intent(in)  :: xlat, xlon, vtype, slmsk,    &
                                                           sfc_alb_pert, lndp_prt_list, &
                                                           landfrac, lakefrac,         &
                                                           snowd, sncovr,               &
                                                           sncovr_ice, fice, zorl,      &
                                                           hprime, tsfg, tsfa, tisfc,   &
                                                           coszen, alvsf, alnsf, alvwf, &
                                                           alnwf, facsf, facwf,         &
                                                           semis_lnd, semis_ice, snoalb
      character(len=3)    , dimension(:),   intent(in)  :: lndp_var_list
      real(kind=kind_phys), dimension(:),   intent(in)  :: albdvis_lnd, albdnir_lnd,    &
                                                           albivis_lnd, albinir_lnd
      real(kind=kind_phys), dimension(:),   intent(in)  :: albdvis_ice, albdnir_ice,    &
                                                           albivis_ice, albinir_ice
      real(kind=kind_phys), dimension(:),   intent(inout) :: semisbase, semis
      real(kind=kind_phys), dimension(:,:), intent(inout) :: sfcalb
      real(kind=kind_phys), dimension(:),   intent(inout) :: sfc_alb_dif
      character(len=*),                     intent(out) :: errmsg
      integer,                              intent(out) :: errflg

      ! Local variables
      integer                             :: i
      real(kind=kind_phys)                :: lndp_alb
      real(kind=kind_phys)                :: cimin
      real(kind=kind_phys), dimension(im) :: fracl, fraci, fraco
      logical,              dimension(im) :: icy

      ! Initialize CCPP error handling variables
      errmsg = ''
      errflg = 0

      ! Return immediately if neither shortwave nor longwave radiation are called
      if (.not. lsswr .and. .not. lslwr) return

      do i=1,im
        if (lakefrac(i) > f_zero) then
          cimin = min_lakeice
        else
          cimin = min_seaice
        endif
      enddo

      ! Set up land/ice/ocean fractions for emissivity and albedo calculations
      if (.not. frac_grid) then
        do i=1,im
          if (slmsk(i) == 1) then
            fracl(i) = f_one
            fraci(i) = f_zero
            fraco(i) = f_zero
            icy(i)   = .false.
          else
            fracl(i) = f_zero
            fraco(i) = f_one
            if(fice(i) < cimin) then
              fraci(i) = f_zero
              icy(i)   = .false.
            else
              fraci(i) = fraco(i) * fice(i)
              icy(i)   = .true.
            endif
            fraco(i) = max(f_zero, fraco(i)-fraci(i))
          endif
        enddo
      else
        do i=1,im
          fracl(i) = landfrac(i)
          fraco(i) = max(f_zero, f_one - fracl(i))
          if(fice(i) < cimin) then
            fraci(i) = f_zero
            icy(i)   = .false.
          else
            fraci(i) = fraco(i) * fice(i)
            icy(i)   = .true.
          endif
          fraco(i) = max(f_zero, fraco(i)-fraci(i))
        enddo
      endif

      if (lslwr) then
!>  - Call module_radiation_surface::setemis(),to set up surface
!! emissivity for LW radiation.
        call setemis (lsm, lsm_noahmp, lsm_ruc, vtype,             &
                      frac_grid, min_seaice, xlon, xlat, slmsk,    &
                      snowd, sncovr, sncovr_ice, zorl, tsfg, tsfa, &
                      hprime, semis_lnd, semis_ice, im,            &
                      fracl, fraco, fraci, icy,                    & !  ---  inputs
                      semisbase, semis)                              !  ---  outputs
      endif

      if (lsswr) then
!>  - Set surface albedo perturbation, if requested
        lndp_alb = -999.
        if (lndp_type==1) then
          do i =1,n_var_lndp
            if (lndp_var_list(i) == 'alb') then
                lndp_alb = lndp_prt_list(i)
            endif
          enddo
        endif

!>  - Call module_radiation_surface::setalb(),to set up surface
!! albedor for SW radiation.

        call setalb (slmsk, lsm, lsm_noahmp, lsm_ruc, snowd, sncovr, sncovr_ice, snoalb, &
                     zorl, coszen, tsfg, tsfa, hprime,           frac_grid, min_seaice,  &
                     alvsf, alnsf, alvwf, alnwf, facsf, facwf, fice, tisfc,              &
                     albdvis_lnd, albdnir_lnd, albivis_lnd, albinir_lnd,                 &
                     albdvis_ice, albdnir_ice, albivis_ice, albinir_ice,                 &
                     IM, sfc_alb_pert, lndp_alb, fracl, fraco, fraci, icy,               & !  ---  inputs
                     sfcalb )                                                              !  ---  outputs

!> -# Approximate mean surface albedo from vis- and nir- diffuse values.
        sfc_alb_dif(:) = max(0.01, 0.5 * (sfcalb(:,2) + sfcalb(:,4)))
      endif

      end subroutine GFS_radiation_surface_run

       subroutine GFS_radiation_surface_finalize ()
       end subroutine GFS_radiation_surface_finalize
!! @}
       end module GFS_radiation_surface
