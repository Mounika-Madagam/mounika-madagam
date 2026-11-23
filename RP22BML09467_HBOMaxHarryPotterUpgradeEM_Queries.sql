/* ==========================================================================
   RP22BML09467 - HBO Max Harry Potter Upgrade (Email)
   Targeting (confirmed with campaign lead):
     customer in ANY of the 5 products  AND  in AT LEAST ONE of the 5 viewership DEs
   Steps: 1 StartingPoint | 2 Inclusion | 3 Duplicates | 4 Segments
          5 Output | 6 Exclusion | 7 Waterfall
   ========================================================================== */


/* ==========================================================================
   STEP 1 - STARTING POINT   (products + viewership targeting only)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint
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
        WHERE s.CUST_TYP = 'DTVI'

        UNION ALL

        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'BYOD' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_A_OV_EXC_StreamCustomer] s
        WHERE s.CUST_TYP = 'BYOD'

        UNION ALL

        SELECT s.ACCT_KEY, s.ACCT_STS, s.CUST_TYP
             , 'UVERSE' AS INPUT_SOURCE
             , s.BAN, s.LST_ACCT_ACTVN_DT
        FROM [P_U_OV_EXC_UverseCustomer] s

        UNION ALL

        SELECT g.ACCT_KEY, g.ACCT_STS, g.CUST_TYP
             , CASE WHEN g.CUST_TYP = 'GENRE-DTVI' THEN 'GENRE_DTVI'
                    ELSE 'GENRE_BYOD' END AS INPUT_SOURCE
             , g.BAN, g.LST_ACCT_ACTVN_DT
        FROM [P_A_OV_EXC_GenreServiceCustomer] g
        WHERE g.CUST_TYP IN ('GENRE-DTVI','GENRE-BYOD')
     ) p
/* Target audience: must be in at least one of the 5 viewership DEs */
JOIN (
        SELECT ACCT_KEY FROM [Family Viewership - VOFAVWR]
        UNION
        SELECT ACCT_KEY FROM [Fantasy Viewership - VOFNVWR]
        UNION
        SELECT ACCT_KEY FROM [Kids Viewership - VOKIVWR]
        UNION
        SELECT ACCT_KEY FROM [Pop Culture Viewership - VOPCVWR]
        UNION
        SELECT ACCT_KEY FROM [Scripted Series Viewership - VOSSVWR]
     ) v
  ON p.ACCT_KEY = v.ACCT_KEY


/* ==========================================================================
   STEP 2 - INCLUSION   (standard marketing + campaign-specific filters + holdout flag)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion
   ========================================================================== */
select i.ACCT_KEY
      ,i.INPUT_SOURCE
      ,e.PREF_EML_TXT
      ,i.LST_ACCT_ACTVN_DT
      ,case when h.ACCT_KEY is not null then 'Y' else 'N' end as HOLDOUT_FLAG   /* in HBO 3 Digit HOG_RD22HOG */
      ,NewID() as RANDOM_ID

from [RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint] i

/* Promotional - Revenue Marketing email eligible */
join [P_A_OV_EXC_EmailMarkElig_Revenue] e
  on i.ACCT_KEY = e.ACCT_KEY

/*Mandatory*/
left join [P_S_LO_EXC_Onboarding] onb
  on i.ACCT_KEY = onb.ACCT_KEY

left join [P_A_OV_AGN_MarketingExclusions] ex
  on i.ACCT_KEY = ex.ACCT_KEY

/*Campaign specific*/
left join [P_A_EV_AGN_AllCustomers_AccountConfig] acac
  on i.ACCT_KEY = acac.ACCT_KEY

/*Holdout flag*/
left join (select distinct ACCT_KEY from [HBO 3 Digit HOG_RD22HOG]) h
  on i.ACCT_KEY = h.ACCT_KEY

where onb.ACCT_KEY is null
  and ex.ACCT_KEY is null
  and not ( isNull(acac.HBO,'N') = 'Y' or isNull(acac.HBO_PAID,'N') = 'Y' )   /* exclude current HBO subs */
  and isNull(acac.BASE_PCKG,'') not like 'PREMIER%'                           /* exclude Premier         */
  and isNull(acac.BASE_PCKG,'') not like 'LO%MAXIMO%'                         /* exclude Lo Maximo       */


/* ==========================================================================
   STEP 3 - DUPLICATES
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates
   One account per email: most recently activated wins
   ========================================================================== */
SELECT i.ACCT_KEY
     , i.INPUT_SOURCE
     , i.PREF_EML_TXT
     , ROW_NUMBER() OVER (
           PARTITION BY i.PREF_EML_TXT
           ORDER BY i.LST_ACCT_ACTVN_DT DESC
                  , CASE WHEN i.INPUT_SOURCE LIKE 'GENRE%' THEN 0 ELSE 1 END
                  , i.ACCT_KEY
                  , i.INPUT_SOURCE
       ) AS EMAIL_RECORD_RANK
FROM [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion] i


/* ==========================================================================
   STEP 4 - SEGMENTS
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Segments
   HOLDOUT_FLAG: Test = N, Control (holdout) = Y
   ========================================================================== */
SELECT
     U.ACCT_KEY
    ,U.INPUT_SOURCE
    ,U.HOLDOUT_FLAG
    ,U.RANDOM_ID
    ,U.PERCENTILE
    ,CASE
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.HOLDOUT_FLAG = 'N' THEN 'S000000010'
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000010'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.HOLDOUT_FLAG = 'N' THEN 'S000000020'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000020'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.HOLDOUT_FLAG = 'N' THEN 'S000000030'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000030'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.HOLDOUT_FLAG = 'N' THEN 'S000000040'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000040'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.HOLDOUT_FLAG = 'N' THEN 'S000000050'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000050'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.HOLDOUT_FLAG = 'N' THEN 'S000000060'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.HOLDOUT_FLAG = 'Y' THEN 'S100000060'
     END AS CELL_CODE
    ,CASE
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.HOLDOUT_FLAG = 'N' THEN 'DTVs Test'
        WHEN U.INPUT_SOURCE = 'DTVSAT'     AND U.HOLDOUT_FLAG = 'Y' THEN 'DTVs Control'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.HOLDOUT_FLAG = 'N' THEN 'DTVi Test'
        WHEN U.INPUT_SOURCE = 'DTVI'       AND U.HOLDOUT_FLAG = 'Y' THEN 'DTVi Control'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.HOLDOUT_FLAG = 'N' THEN 'BYOD Test'
        WHEN U.INPUT_SOURCE = 'BYOD'       AND U.HOLDOUT_FLAG = 'Y' THEN 'BYOD Control'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.HOLDOUT_FLAG = 'N' THEN 'U Verse Test'
        WHEN U.INPUT_SOURCE = 'UVERSE'     AND U.HOLDOUT_FLAG = 'Y' THEN 'U Verse Control'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.HOLDOUT_FLAG = 'N' THEN 'Genre-DTVi Test'
        WHEN U.INPUT_SOURCE = 'GENRE_DTVI' AND U.HOLDOUT_FLAG = 'Y' THEN 'Genre-DTVi Control'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.HOLDOUT_FLAG = 'N' THEN 'Genre-BYOD Test'
        WHEN U.INPUT_SOURCE = 'GENRE_BYOD' AND U.HOLDOUT_FLAG = 'Y' THEN 'Genre-BYOD Control'
     END AS CELL_NAME
    ,U.VENDOR_CODE
FROM (
        SELECT i.ACCT_KEY
              ,i.INPUT_SOURCE
              ,i.HOLDOUT_FLAG
              ,'SFMC' AS VENDOR_CODE
              ,i.RANDOM_ID
              ,ntile(100) OVER (PARTITION BY i.Input_Source ORDER BY i.RANDOM_ID) AS PERCENTILE
        FROM [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Inclusion] AS i    /* live email eligible Data Extension */
        JOIN [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates] AS d   /* used to remove dups Data Extension */
          ON i.ACCT_KEY = d.ACCT_KEY
         AND i.INPUT_SOURCE = d.INPUT_SOURCE
        WHERE d.EMAIL_RECORD_RANK = 1   /* limit to the "best" account per email to remove dups */
) AS U


/* ==========================================================================
   STEP 5 - OUTPUT   (test only - no control)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Output
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
  and s.HOLDOUT_FLAG = 'N'   /* test only - holdout control accounts are not sent */


/* ==========================================================================
   STEP 6 - EXCLUSION   (mirror of Inclusion: mandatory first, then campaign-specific)
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Exclusion
   ========================================================================== */
select sp.ACCT_KEY
      ,case  when o.ACCT_KEY is not null and sg.ACCT_KEY is not null then 'FINAL OUTPUT QUANTITY'
             when e.ACCT_KEY is null then '02. Excluded: Not Base marketing email eligible (no email, opt out, non-responder, etc.)'
             when onb.ACCT_KEY is not null then '03. Excluded: Account is still within the Onboarding period'
             when ex.ACCT_KEY is not null then '04. Excluded: Account in MDU & Employees'
             when isNull(acac.HBO,'N') = 'Y' or isNull(acac.HBO_PAID,'N') = 'Y' then '05. Excluded: Current HBO subscriber'
             when isNull(acac.BASE_PCKG,'') like 'PREMIER%' or isNull(acac.BASE_PCKG,'') like 'LO%MAXIMO%' then '06. Excluded: Base package is Premier or Lo Maximo'
             when d.EMAIL_RECORD_RANK > 1 then '07. Excluded: Email address shared across multiple accounts. Deduped to the most recently activated account'
             when sg.HOLDOUT_FLAG = 'Y' then '08. Excluded: Holdout control group (HBO 3 Digit HOG_RD22HOG)'
             else 'ERROR: No Valid Reason'
       end REASON

from [RP22BML09467_HBOMaxHarryPotterUpgradeEM_StartingPoint] sp
left join [P_A_OV_EXC_EmailMarkElig_Revenue] e on sp.ACCT_KEY = e.ACCT_KEY

/*Mandatory*/
left join [P_S_LO_EXC_Onboarding] onb on sp.ACCT_KEY = onb.ACCT_KEY

left join [P_A_OV_AGN_MarketingExclusions] ex on sp.ACCT_KEY = ex.ACCT_KEY

/*Campaign specific*/
left join [P_A_EV_AGN_AllCustomers_AccountConfig] acac on sp.ACCT_KEY = acac.ACCT_KEY

left join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Duplicates] d on sp.ACCT_KEY = d.ACCT_KEY and sp.INPUT_SOURCE = d.INPUT_SOURCE

left join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Segments] sg on sp.ACCT_KEY = sg.ACCT_KEY and sp.INPUT_SOURCE = sg.INPUT_SOURCE

left join [RP22BML09467_HBOMaxHarryPotterUpgradeEM_Output] o on sp.ACCT_KEY = o.ACCT_KEY


/* ==========================================================================
   STEP 7 - WATERFALL
   Target DE : RP22BML09467_HBOMaxHarryPotterUpgradeEM_Waterfall
   ========================================================================== */
select '02. Excluded: Not Base marketing email eligible (no email, opt out, non-responder, etc.)' as REASON, 0 as RECORDS
UNION
select '03. Excluded: Account is still within the Onboarding period' as REASON, 0 as RECORDS
UNION
select '04. Excluded: Account in MDU & Employees' as REASON, 0 as RECORDS
UNION
select '05. Excluded: Current HBO subscriber' as REASON, 0 as RECORDS
UNION
select '06. Excluded: Base package is Premier or Lo Maximo' as REASON, 0 as RECORDS
UNION
select '07. Excluded: Email address shared across multiple accounts. Deduped to the most recently activated account' as REASON, 0 as RECORDS
UNION
select '08. Excluded: Holdout control group (HBO 3 Digit HOG_RD22HOG)' as REASON, 0 as RECORDS
UNION
select 'FINAL OUTPUT QUANTITY' as REASON, 0 as RECORDS
UNION
select 'ERROR: No Valid Reason' as REASON, 0 as RECORDS
