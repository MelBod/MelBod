
     SELECT DISTINCT cea.EpiId AS EpisodeId
          ,pp.PpPeriodnumber
          ,pp.PpStartDate
          ,pp.PpEndDate
          ,rp.RpId
          ,rp.RpCode
          ,rp.RpSoeEffectiveFrom
          ,rp.RpSoeEffectiveTo
     
     FROM dbo.ClientEpisodesAll cea
     
     INNER JOIN dbo.ClientEpisodeFs cefs
          ON cea.EpiId = cefs.CefsEpiId
               AND /*cefs.CefsPs = 'P' and*/ cea.SourceSystem = cefs.SourceSystem
     
     INNER JOIN dbo.PdgmPeriod pp
          ON cefs.CefsId = pp.PpCefsId
               AND pp.PpDeleted = 0
               AND cefs.SourceSystem = pp.SourceSystem
     
     INNER JOIN dbo.RatePeriod rp
          ON pp.PpStartDate BETWEEN rp.RpSoeEffectiveFrom
                    AND rp.RpSoeEffectiveTo
               AND rp.RpActive = 'Y'
               AND rp.RpSltId = 1
               AND rp.RpRptId = 5
               AND cea.SourceSystem = rp.SourceSystem
     
     WHERE cea.EpiSlId = 1
	 AND     pp.PpStartDate = '2025-11-20'