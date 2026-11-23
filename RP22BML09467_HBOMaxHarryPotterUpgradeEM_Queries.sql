/* ==========================================================================
   RP22BML09467 - HBO Max Harry Potter Upgrade (Email)
   Targets: Satellite (DTVSAT), DTVi, BYOD, U-verse, Genre Packs
   Placeholders to replace are marked  <<< REPLACE >>>
   ========================================================================== */


/* ==========================================================================
   STEP 1 - STARTING POINT
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint
   Data Action: Overwrite
   Product pull (5 DEs) + HBO sub / Premier / LO Maximo exclusion
   ========================================================================== */
SELECT p.ACCT_KEY
     , p.ACCT_STS
     , p.CUST_TYP
     , p.INPUT_SOURCE
     , p.BAN
     , p.LST_ACCT_ACTVN_DT
FROM (
        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'DTVSAT' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_S_OV_EXC_SatelliteCustomer] s

        UNION ALL

        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'DTVI' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_A_OV_EXC_StreamCustomer] s
        WHERE s.<<< REPLACE: DTVi/BYOD field >>> = '<<< DTVi value >>>'

        UNION ALL

        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'BYOD' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_A_OV_EXC_StreamCustomer] s
        WHERE s.<<< REPLACE: DTVi/BYOD field >>> = '<<< BYOD value >>>'

        UNION ALL

        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'UVERSE' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_U_OV_EXC_UverseCustomer] s

        UNION ALL

        /* Genre Packs - one DE (GenreServiceCustomer), target = any of the 5 viewership flags;
           split into the two genre cells (DTVi / BYOD)                    */
        SELECT g.ACCT_KEY, g.ACCT_STS, g.CUST_TYP
             , CASE WHEN g.<<< REPLACE: device field >>> = 'DTVI'
                    THEN 'GENRE_DTVI' ELSE 'GENRE_BYOD' END AS INPUT_SOURCE
             , g.BAN, g.LST_ACCT_ACTVN_DT
        FROM [P_A_OV_EXC_GenreServiceCustomer] g
        WHERE ( g.VOFAVWR = 'Y'      /* Family Viewership        */
             OR g.VOFNVWR = 'Y'      /* Fantasy Viewership       */
             OR g.VOKIVWR = 'Y'      /* Kids Viewership          */
             OR g.VOPCVWR = 'Y'      /* Pop Culture Viewership   */
             OR g.VOSSVWR = 'Y' )    /* Scripted Series Viewership */
     ) p
JOIN [P_A_EV_AGN_AllCustomers_AccountConfig] acac
  ON p.ACCT_KEY = acac.ACCT_KEY
WHERE NOT ( isNull(acac.HBO,'N') = 'Y' OR isNull(acac.HBO_PAID,'N') = 'Y' )  /* exclude current HBO subs */
  AND acac.BASE_PCKG NOT LIKE 'PREMIER%'                                       /* exclude Premier         */
  AND acac.BASE_PCKG NOT LIKE 'LO%MAXIMO%'                                     /* exclude Lo Maximo       */


/* ==========================================================================
   STEP 2 - INCLUSION
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion
   Data Action: Overwrite
   Promotional - Revenue Marketing email eligibility (P_A_OV_EXC_EmailMarkElig_Revenue)
   + mandatory marketing exclusions / onboarding (emp / MDU suppressed here)
   ========================================================================== */
select i.ACCT_KEY
      ,i.INPUT_SOURCE
      ,e.PREF_EML_TXT
      ,i.LST_ACCT_ACTVN_DT
      ,NewID() as RANDOM_ID

from [RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint] i
join [P_A_OV_EXC_EmailMarkElig_Revenue] e
  on i.ACCT_KEY = e.ACCT_KEY

/*Mandatory*/
left join [P_A_OV_AGN_MarketingExclusions] ex
  on i.ACCT_KEY = ex.ACCT_KEY

left join [P_S_LO_EXC_Onboarding] onb
  on i.ACCT_KEY = onb.ACCT_KEY

where ex.ACCT_KEY is null
  and onb.ACCT_KEY is null


/* ==========================================================================
   STEP 3 - DUPLICATES
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates
   Data Action: Overwrite
   One account per email address (genre accounts win ties, then most recent)
   ========================================================================== */
SELECT i.ACCT_KEY
     , i.INPUT_SOURCE
     , i.PREF_EML_TXT
     , ROW_NUMBER() OVER (
           PARTITION BY i.PREF_EML_TXT
           ORDER BY CASE WHEN i.INPUT_SOURCE LIKE 'GENRE%' THEN 0 ELSE 1 END
                  , i.LST_ACCT_ACTVN_DT DESC
                  , i.ACCT_KEY
       ) AS EMAIL_RECORD_RANK
FROM [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion] i


/* ==========================================================================
   STEP 4 - SEGMENTS
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Segments
   Data Action: Overwrite
   Control = HBO 3 Digit HOG_RD22HOG holdout; Test = everyone else
   Cell codes per Cell Code Matrix
   ========================================================================== */
SELECT
     U.ACCT_KEY
    ,U.INPUT_SOURCE
    ,U.CONTROL_FLAG
    ,U.RANDOM_ID
    ,U.PERCENTILE
    ,CASE
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.CONTROL_FLAG = 'N' THEN 'S000000010'
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.CONTROL_FLAG = 'Y' THEN 'S100000010'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.CONTROL_FLAG = 'N' THEN 'S000000020'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.CONTROL_FLAG = 'Y' THEN 'S100000020'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.CONTROL_FLAG = 'N' THEN 'S000000030'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.CONTROL_FLAG = 'Y' THEN 'S100000030'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.CONTROL_FLAG = 'N' THEN 'S000000040'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.CONTROL_FLAG = 'Y' THEN 'S100000040'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.CONTROL_FLAG = 'N' THEN 'S000000050'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.CONTROL_FLAG = 'Y' THEN 'S100000050'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.CONTROL_FLAG = 'N' THEN 'S000000060'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.CONTROL_FLAG = 'Y' THEN 'S100000060'
     END AS CELL_CODE
    ,CASE
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.CONTROL_FLAG = 'N' THEN 'DTVs Test'
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.CONTROL_FLAG = 'Y' THEN 'DTVs Control'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.CONTROL_FLAG = 'N' THEN 'DTVi Test'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.CONTROL_FLAG = 'Y' THEN 'DTVi Control'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.CONTROL_FLAG = 'N' THEN 'BYOD Test'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.CONTROL_FLAG = 'Y' THEN 'BYOD Control'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.CONTROL_FLAG = 'N' THEN 'U Verse Test'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.CONTROL_FLAG = 'Y' THEN 'U Verse Control'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.CONTROL_FLAG = 'N' THEN 'Genre-DTVi Test'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.CONTROL_FLAG = 'Y' THEN 'Genre-DTVi Control'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.CONTROL_FLAG = 'N' THEN 'Genre-BYOD Test'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.CONTROL_FLAG = 'Y' THEN 'Genre-BYOD Control'
     END AS CELL_NAME
    ,U.VENDOR_CODE
FROM (
        SELECT i.ACCT_KEY
              ,i.INPUT_SOURCE
              ,CASE WHEN h.ACCT_KEY IS NOT NULL THEN 'Y' ELSE 'N' END AS CONTROL_FLAG   /* in HOG_RD22HOG = control */
              ,'SFMC' AS VENDOR_CODE
              ,i.RANDOM_ID
              ,ntile(100) OVER (PARTITION BY i.Input_Source ORDER BY i.RANDOM_ID) AS PERCENTILE
        FROM [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion] AS i    /* live email eligible Data Extension */
        JOIN [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates] AS d   /* used to remove dups Data Extension */
          ON i.ACCT_KEY = d.ACCT_KEY
         AND i.INPUT_SOURCE = d.INPUT_SOURCE
        LEFT JOIN [<<< REPLACE: HBO 3 Digit HOG_RD22HOG holdout DE >>>] h
          ON i.ACCT_KEY = h.ACCT_KEY
        WHERE d.EMAIL_RECORD_RANK = 1   /* limit to the "best" account per email to remove dups */
) AS U


/* ==========================================================================
   STEP 5 - OUTPUT
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Output
   Data Action: Overwrite
   ========================================================================== */
select e.BAN
      ,i.PREF_EML_TXT EMAIL_ADDRESS
      ,e.FIRST_NAME
      ,e.CRM_ACCT_ID
      ,e.CRM_CONTCT_ID
      ,s.CELL_CODE
      ,s.CELL_NAME
      ,cd.CAMP_CODE
      ,cd.CAMP_NAME
      ,cd.INTAKE_ID
      ,i.ACCT_KEY
      ,cd.EXECUTION_ID
      ,cd.EXECUTION_DT
      ,aci.HH_ID
      ,aci.CORE_ID
      ,e.MAGIC_LNK_TOKN

from [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion] i
join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Segments] s on i.ACCT_KEY = s.ACCT_KEY and i.INPUT_SOURCE = s.INPUT_SOURCE
join [P_A_OV_EXC_EmailMarkElig_Revenue] e on i.ACCT_KEY = e.ACCT_KEY
join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_CampaignDetails] cd on cd.INTAKE_ID = 'RP22BML09467'
left join [P_A_EV_AGN_AllCustomers_Identity] aci on i.ACCT_KEY = aci.ACCT_KEY

where s.CELL_CODE is not null


/* ==========================================================================
   STEP 6 - EXCLUSION (QC / waterfall detail)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Exclusion
   Data Action: Overwrite
   ========================================================================== */
select sp.ACCT_KEY
      ,case  when o.ACCT_KEY is not null then 'FINAL OUTPUT QUANTITY'
             when e.ACCT_KEY is null then '02. Excluded: Not Base marketing email eligible (no email, opt out, non-responder, etc.)'
             when onb.ACCT_KEY is not null then '03. Excluded: Account is still within the Onboarding period'
             when ex.ACCT_KEY is not null then '04. Excluded: Account in MDU & Employees'
             when d.EMAIL_RECORD_RANK > 1 then '05. Excluded: Email address shared across multiple accounts. Deduped to the most recently activated account'
             else 'ERROR: No Valid Reason'
       end REASON

from [RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint] sp
left join [P_A_OV_EXC_EmailMarkElig_Revenue] e on sp.ACCT_KEY = e.ACCT_KEY

left join [P_S_LO_EXC_Onboarding] onb on sp.ACCT_KEY = onb.ACCT_KEY

left join [P_A_OV_AGN_MarketingExclusions] ex on sp.ACCT_KEY = ex.ACCT_KEY

left join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates] d on sp.ACCT_KEY = d.ACCT_KEY and sp.INPUT_SOURCE = d.INPUT_SOURCE

left join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Output] o on sp.ACCT_KEY = o.ACCT_KEY


/* ==========================================================================
   STEP 7 - WATERFALL (unchanged from clone)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Waterfall
   ========================================================================== */
select '02. Excluded: Not Base marketing email eligible (no email, opt out, non-responder, etc.)' as REASON, 0 as RECORDS
UNION
select '03. Excluded: Account is still within the Onboarding period' as REASON, 0 as RECORDS
UNION
select '04. Excluded: Account in MDU & Employees' as REASON, 0 as RECORDS
UNION
select '05. Excluded: Email address shared across multiple accounts. Deduped to the most recently activated account' as REASON, 0 as RECORDS
UNION
select 'FINAL OUTPUT QUANTITY' as REASON, 0 as RECORDS
UNION
select 'ERROR: No Valid Reason' as REASON, 0 as RECORDS
