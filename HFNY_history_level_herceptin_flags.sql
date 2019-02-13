/*	Here we have the flags established as of 2/7 @ 1:30 pm in one all-purpose query.  HUZZAH!	*/
SELECT
		member_ID
	,	first_DOS
	,	SUM( wasted_units )										AS	count_of_wasted_units
	,	SUM( administered_units )								AS	count_of_administered_units
	,	count_of_wasted_units + count_of_administered_units
																AS	TOTAL_UNITS
	,	SUM( paid_for_wasted )									AS	paid_for_wasted_units
	,	SUM( paid_for_administered )							AS	paid_for_administered_units
	,	paid_for_wasted_units + paid_for_administered_units
																AS	TOTAL_PAID
	,	SUM( allowed_amount )									AS	total_allowed_amount
	,	MIN( disposition_of_modifier )							AS	min_dom
	,	MAX( disposition_of_modifier )							AS	max_dom	
	,	COUNT( first_DOS ) OVER ( PARTITION BY member_ID )		AS	total_dosage_count
	,	FIRST_VALUE( first_DOS )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose_date
	,	FIRST_VALUE( count_of_administered_units )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose
	,	LAST_VALUE( count_of_administered_units ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose
	,	LAST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose_date
	,	DATEDIFF( DAY, prev_dose_date, first_DOS )				AS	days_since_prev_dose
	,	FIRST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING )
																AS	next_dose_date
	,	DATEDIFF( DAY, first_DOS, next_dose_date )				AS	days_till_next_dose
	,	DATEDIFF( DAY, loading_dose_date, first_DOS ) = days_since_prev_dose
																AS	first_dose_after_loading
	,	( prev_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
																AS	prev_ratio
	,	( count_of_administered_units::FLOAT / days_till_next_dose::FLOAT )::FLOAT
																AS	subs_ratio
	,	CASE	count_of_administered_units
			WHEN	0	THEN	1
			ELSE				( prev_ratio::FLOAT / subs_ratio::FLOAT )::FLOAT
		END														AS	test_ratio
	,	CASE	(		count_of_administered_units > 95
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_A	--	single dose of more than 95 units in time window
	,	CASE	( prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( count_of_administered_units::FLOAT / prev_dose::FLOAT )::FLOAT
		END														AS	dosage_change_factor
	,	CASE	( days_since_prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( days_till_next_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
		END														AS	administration_gap_factor
	,	CASE	(		count_of_administered_units IN ( 44, 88 )
					AND	date_in_time_window							)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_B	--	single dose of 44 or 88 units in time window
	,	CASE	(		count_of_administered_units = 0
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_C	--	zero units administered in time window
	,	CASE	date_in_time_window
			WHEN	TRUE	THEN	MAX( abnormality_pre_flag_D )
			ELSE					'0'
		END														AS	abnormality_flag_D	--	units less than 5.0 not labelled waste (JW) in time window
	,	CASE	(		count_of_administered_units IN ( 15, 30, 45, 60, 75, 90 )
					AND	date_in_time_window											)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_E	--	units a multiple of 15 in time window
	,	CASE		date_in_time_window
				AND	NOT	first_dose_after_loading
				AND	count_of_administered_units		>	0
				AND	prev_dose						>	0
				AND	(		test_ratio				>=	1.5
						OR	test_ratio				<=	0.666666667	)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_F	--	sudden break in units per day during time window
	,	CASE		date_in_time_window
				AND	dosage_change_factor		>=	2.0
				AND	administration_gap_factor	>=	0.9
				AND	administration_gap_factor	<=	1.1
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_G	--	doubled units without doubled time gap (roughly), during time window
FROM
	(	SELECT
				claims.ClaimNumber			AS	claim_ID
			,	claims.MemberID				AS	member_ID
			,	claims.LineNumber			AS	line_num
			,	CASE	claims.ClaimStatus
					WHEN	'D'	THEN	'unpaid'
					WHEN	'F'	THEN	'paid'
				END							AS	claim_payment_status
			,	CASE	claims.CPTCode1
					WHEN	'J9355'	THEN	'herceptin'
					ELSE					NULL
				END							AS	administered
			,	claims.ProcedureCodeModifier1
			,	CASE	claims.ProcedureCodeModifier1	IS	NULL
					WHEN	TRUE	THEN	'pcm_IS_null'
					ELSE					'pcm_NOT_null'
				END							AS	disposition_of_modifier
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	wasted_units
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	administered_units
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_wasted
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_administered
			,	claims.Units				AS	units
			,	claims.ClaimPaidAmount		AS	paid_amount
			,	claims.ClaimAllowedAmount	AS	allowed_amount
			,	claims.FirstDOS				AS	first_DOS
			,	CASE		(		units::float			<	5.0		)
						AND	(		ProcedureCodeModifier1	!=	'JW'
								OR	ProcedureCodeModifier1	IS	NULL	)
					WHEN	TRUE	THEN	'1'
					WHEN	FALSE	THEN	'0'
				END							AS	abnormality_pre_flag_D
			,	( DATEDIFF( DAY, '2017-05-01', first_DOS )	>=	0 )
											AS	date_in_time_window
		FROM
					ESRD_clean_raw.medical_claims							claims
			JOIN	(	SELECT DISTINCT	member_ID
						FROM			whaight.HFNY_herc_claims_clean	)	herc
			ON		claims.MemberID	=	herc.member_ID
		WHERE
				claim_payment_status	=	'paid'
			AND	administered			=	'herceptin'
			AND	paid_amount				>	0
	)
GROUP BY
		member_ID
	,	first_DOS
	,	date_in_time_window
ORDER BY
		member_ID	ASC
	,	first_DOS	ASC
;



/*	This query pulls all lines in which at least one of thee flags is set.	*/
SELECT	*
FROM
(
SELECT
		member_ID
	,	first_DOS
	,	SUM( wasted_units )										AS	count_of_wasted_units
	,	SUM( administered_units )								AS	count_of_administered_units
	,	count_of_wasted_units + count_of_administered_units
																AS	TOTAL_UNITS
	,	SUM( paid_for_wasted )									AS	paid_for_wasted_units
	,	SUM( paid_for_administered )							AS	paid_for_administered_units
	,	paid_for_wasted_units + paid_for_administered_units
																AS	TOTAL_PAID
	,	SUM( allowed_amount )									AS	total_allowed_amount
	,	MIN( disposition_of_modifier )							AS	min_dom
	,	MAX( disposition_of_modifier )							AS	max_dom	
	,	COUNT( first_DOS ) OVER ( PARTITION BY member_ID )		AS	total_dosage_count
	,	FIRST_VALUE( first_DOS )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose_date
	,	FIRST_VALUE( count_of_administered_units )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose
	,	LAST_VALUE( count_of_administered_units ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose
	,	LAST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose_date
	,	DATEDIFF( DAY, prev_dose_date, first_DOS )				AS	days_since_prev_dose
	,	FIRST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING )
																AS	next_dose_date
	,	DATEDIFF( DAY, first_DOS, next_dose_date )				AS	days_till_next_dose
	,	DATEDIFF( DAY, loading_dose_date, first_DOS ) = days_since_prev_dose
																AS	first_dose_after_loading
	,	( prev_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
																AS	prev_ratio
	,	( count_of_administered_units::FLOAT / days_till_next_dose::FLOAT )::FLOAT
																AS	subs_ratio
	,	CASE	count_of_administered_units
			WHEN	0	THEN	1
			ELSE				( prev_ratio::FLOAT / subs_ratio::FLOAT )::FLOAT
		END														AS	test_ratio
	,	CASE	(		count_of_administered_units > 95
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_A	--	single dose of more than 95 units in time window
	,	CASE	( prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( count_of_administered_units::FLOAT / prev_dose::FLOAT )::FLOAT
		END														AS	dosage_change_factor
	,	CASE	( days_since_prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( days_till_next_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
		END														AS	administration_gap_factor
	,	CASE	(		count_of_administered_units IN ( 44, 88 )
					AND	date_in_time_window							)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_B	--	single dose of 44 or 88 units in time window
	,	CASE	(		count_of_administered_units = 0
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_C	--	zero units administered in time window
	,	CASE	date_in_time_window
			WHEN	TRUE	THEN	MAX( abnormality_pre_flag_D )
			ELSE					'0'
		END														AS	abnormality_flag_D	--	units less than 5.0 not labelled waste (JW) in time window
	,	CASE	(		count_of_administered_units IN ( 15, 30, 45, 60, 75, 90 )
					AND	date_in_time_window											)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_E	--	units a multiple of 15 in time window
	,	CASE		date_in_time_window
				AND	NOT	first_dose_after_loading
				AND	count_of_administered_units		>	0
				AND	prev_dose						>	0
				AND	(		test_ratio				>=	1.5
						OR	test_ratio				<=	0.666666667	)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_F	--	sudden break in units per day during time window
	,	CASE		date_in_time_window
				AND	dosage_change_factor		>=	1.5
				AND	administration_gap_factor	>=	0.9
				AND	administration_gap_factor	<=	1.1
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_G	--	doubled units without doubled time gap (roughly), during time window
FROM
	(	SELECT
				claims.ClaimNumber			AS	claim_ID
			,	claims.MemberID				AS	member_ID
			,	claims.LineNumber			AS	line_num
			,	CASE	claims.ClaimStatus
					WHEN	'D'	THEN	'unpaid'
					WHEN	'F'	THEN	'paid'
				END							AS	claim_payment_status
			,	CASE	claims.CPTCode1
					WHEN	'J9355'	THEN	'herceptin'
					ELSE					NULL
				END							AS	administered
			,	claims.ProcedureCodeModifier1
			,	CASE	claims.ProcedureCodeModifier1	IS	NULL
					WHEN	TRUE	THEN	'pcm_IS_null'
					ELSE					'pcm_NOT_null'
				END							AS	disposition_of_modifier
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	wasted_units
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	administered_units
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_wasted
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_administered
			,	claims.Units				AS	units
			,	claims.ClaimPaidAmount		AS	paid_amount
			,	claims.ClaimAllowedAmount	AS	allowed_amount
			,	claims.FirstDOS				AS	first_DOS
			,	CASE		(		units::float			<	5.0		)
						AND	(		ProcedureCodeModifier1	!=	'JW'
								OR	ProcedureCodeModifier1	IS	NULL	)
					WHEN	TRUE	THEN	'1'
					WHEN	FALSE	THEN	'0'
				END							AS	abnormality_pre_flag_D
			,	( DATEDIFF( DAY, '2017-05-01', first_DOS )	>=	0 )
											AS	date_in_time_window
		FROM
					ESRD_clean_raw.medical_claims							claims
			JOIN	(	SELECT DISTINCT	member_ID
						FROM			whaight.HFNY_herc_claims_clean	)	herc
			ON		claims.MemberID	=	herc.member_ID
		WHERE
				claim_payment_status	=	'paid'
			AND	administered			=	'herceptin'
			AND	paid_amount				>	0
	)
GROUP BY
		member_ID
	,	first_DOS
	,	date_in_time_window
ORDER BY
		member_ID	ASC
	,	first_DOS	ASC
)
WHERE
		abnormality_flag_A	=	'1'
	OR	abnormality_flag_B	=	'1'
	OR	abnormality_flag_C	=	'1'
	OR	abnormality_flag_D	=	'1'
	OR	abnormality_flag_E	=	'1'
	OR	abnormality_flag_F	=	'1'
	OR	abnormality_flag_G	=	'1'
;
/* FLAGGED 	1010	ROWS	*/



/*	Count the rows where each flag is set 	*/
SELECT
		SUM( abnormality_flag_A )	AS	flag_A
	,	SUM( abnormality_flag_B )	AS	flag_B
	,	SUM( abnormality_flag_C )	AS	flag_C
	,	SUM( abnormality_flag_D )	AS	flag_D
	,	SUM( abnormality_flag_E )	AS	flag_E
	,	SUM( abnormality_flag_F )	AS	flag_F
	,	SUM( abnormality_flag_G )	AS	flag_G
FROM
(
SELECT
		member_ID
	,	first_DOS
	,	SUM( wasted_units )										AS	count_of_wasted_units
	,	SUM( administered_units )								AS	count_of_administered_units
	,	count_of_wasted_units + count_of_administered_units
																AS	TOTAL_UNITS
	,	SUM( paid_for_wasted )									AS	paid_for_wasted_units
	,	SUM( paid_for_administered )							AS	paid_for_administered_units
	,	paid_for_wasted_units + paid_for_administered_units
																AS	TOTAL_PAID
	,	SUM( allowed_amount )									AS	total_allowed_amount
	,	MIN( disposition_of_modifier )							AS	min_dom
	,	MAX( disposition_of_modifier )							AS	max_dom	
	,	COUNT( first_DOS ) OVER ( PARTITION BY member_ID )		AS	total_dosage_count
	,	FIRST_VALUE( first_DOS )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose_date
	,	FIRST_VALUE( count_of_administered_units )
			OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																AS	loading_dose
	,	LAST_VALUE( count_of_administered_units ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose
	,	LAST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																AS	prev_dose_date
	,	DATEDIFF( DAY, prev_dose_date, first_DOS )				AS	days_since_prev_dose
	,	FIRST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
					ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING )
																AS	next_dose_date
	,	DATEDIFF( DAY, first_DOS, next_dose_date )				AS	days_till_next_dose
	,	DATEDIFF( DAY, loading_dose_date, first_DOS ) = days_since_prev_dose
																AS	first_dose_after_loading
	,	( prev_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
																AS	prev_ratio
	,	( count_of_administered_units::FLOAT / days_till_next_dose::FLOAT )::FLOAT
																AS	subs_ratio
	,	CASE	count_of_administered_units
			WHEN	0	THEN	1
			ELSE				( prev_ratio::FLOAT / subs_ratio::FLOAT )::FLOAT
		END														AS	test_ratio
	,	CASE	(		count_of_administered_units > 95
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_A	--	single dose of more than 95 units in time window	#2
	,	CASE	( prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( count_of_administered_units::FLOAT / prev_dose::FLOAT )::FLOAT
		END														AS	dosage_change_factor
	,	CASE	( days_since_prev_dose = 0 )
			WHEN	TRUE	THEN	1.0
			ELSE					( days_till_next_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
		END														AS	administration_gap_factor
	,	CASE	(		count_of_administered_units IN ( 44, 88 )
					AND	date_in_time_window							)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_B	--	single dose of 44 or 88 units in time window	#3
	,	CASE	(		count_of_administered_units = 0
					AND	date_in_time_window					)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_C	--	zero units administered in time window		#20
	,	CASE	date_in_time_window
			WHEN	TRUE	THEN	MAX( abnormality_pre_flag_D )
			ELSE					'0'
		END														AS	abnormality_flag_D	--	units less than 5.0 not labelled waste (JW) in time window	#7
	,	CASE	(		count_of_administered_units IN ( 15, 30, 45, 60, 75, 90 )
					AND	date_in_time_window											)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_E	--	units a multiple of 15 in time window	#6
	,	CASE		date_in_time_window
				AND	NOT	first_dose_after_loading
				AND	count_of_administered_units		>	0
				AND	prev_dose						>	0
				AND	(		test_ratio				>=	1.5
						OR	test_ratio				<=	0.666666667	)
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_F	--	sudden break in units per day during time window	#4
	,	CASE		date_in_time_window
				AND	dosage_change_factor		>=	1.5
				AND	administration_gap_factor	>=	0.9
				AND	administration_gap_factor	<=	1.1
			WHEN	TRUE	THEN	'1'
			ELSE					'0'
		END														AS	abnormality_flag_G	--	doubled units without doubled time gap (roughly), during time window	#1
FROM
	(	SELECT
				claims.ClaimNumber			AS	claim_ID
			,	claims.MemberID				AS	member_ID
			,	claims.LineNumber			AS	line_num
			,	CASE	claims.ClaimStatus
					WHEN	'D'	THEN	'unpaid'
					WHEN	'F'	THEN	'paid'
				END							AS	claim_payment_status
			,	CASE	claims.CPTCode1
					WHEN	'J9355'	THEN	'herceptin'
					ELSE					NULL
				END							AS	administered
			,	claims.ProcedureCodeModifier1
			,	CASE	claims.ProcedureCodeModifier1	IS	NULL
					WHEN	TRUE	THEN	'pcm_IS_null'
					ELSE					'pcm_NOT_null'
				END							AS	disposition_of_modifier
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	wasted_units
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.Units::FLOAT
					WHEN	FALSE	THEN	0.0
				END							AS	administered_units
			,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
							AND	claims.ProcedureCodeModifier1	=	'JW'			)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_wasted
			,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
							OR	(		disposition_of_modifier			=	'pcm_NOT_null'
									AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
					WHEN	TRUE	THEN	claims.ClaimPaidAmount
					WHEN	FALSE	THEN	0.0
				END							AS	paid_for_administered
			,	claims.Units				AS	units
			,	claims.ClaimPaidAmount		AS	paid_amount
			,	claims.ClaimAllowedAmount	AS	allowed_amount
			,	claims.FirstDOS				AS	first_DOS
			,	CASE		(		units::float			<	5.0		)
						AND	(		ProcedureCodeModifier1	!=	'JW'
								OR	ProcedureCodeModifier1	IS	NULL	)
					WHEN	TRUE	THEN	'1'
					WHEN	FALSE	THEN	'0'
				END							AS	abnormality_pre_flag_D
			,	( DATEDIFF( DAY, '2017-05-01', first_DOS )	>=	0 )
											AS	date_in_time_window
		FROM
					ESRD_clean_raw.medical_claims							claims
			JOIN	(	SELECT DISTINCT	member_ID
						FROM			whaight.HFNY_herc_claims_clean	)	herc
			ON		claims.MemberID	=	herc.member_ID
		WHERE
				claim_payment_status	=	'paid'
			AND	administered			=	'herceptin'
			AND	paid_amount				>	0
	)
GROUP BY
		member_ID
	,	first_DOS
	,	date_in_time_window
ORDER BY
		member_ID	ASC
	,	first_DOS	ASC
)
;
/*	flag_a	flag_b	flag_c	flag_d	flag_e	flag_f	flag_g	*/
/*	17		36		0		129		679		359		39 		*/


/*	CAN'T!	CAN'T!	CAN'T!	CAN'T!	CAN'T!	CAN'T!	CAN'T!	CAN'T!	CAN'T!		*/
/*	left join with ESRD_clean_raw.medical_claims to get all the pertinent info.	*/
SELECT
		baseTable.member_ID
	,	baseTable.first_DOS
	,	baseTable.count_of_wasted_units
	,	baseTable.count_of_administered_units
	,	baseTable.TOTAL_UNITS
	,	baseTable.paid_for_wasted_units
	,	baseTable.paid_for_administered_units
	,	baseTable.TOTAL_PAID
	,	baseTable.total_allowed_amount
	,	baseTable.loading_dose_date
	,	baseTable.loading_dose
	,	baseTable.prev_dose
	,	baseTable.prev_dose_date
	,	baseTable.days_since_prev_dose
	,	baseTable.next_dose_date
	,	baseTable.days_till_next_dose
	,	baseTable.prev_ratio
	,	baseTable.subs_ratio
	,	baseTable.test_ratio
	,	baseTable.dosage_change_factor
	,	baseTable.administration_gap_factor
	,	baseTable.abnormality_flag_A
	,	baseTable.abnormality_flag_B
	,	baseTable.abnormality_flag_C
	,	baseTable.abnormality_flag_D
	,	baseTable.abnormality_flag_E
	,	baseTable.abnormality_flag_F
	,	baseTable.abnormality_flag_G
	,	crmc.CPTCode1
	,	crmc.ClaimSubmittedChargeAmount
	,	crmc.LineNumber
	,	crmc.ProcedureCode
	,	crmc.ProcedureCodeModifier1
	,	crmc.ProcedureCodeModifier2
	,	crmc.Units
	,	crmc.dhp_proc_code
FROM
		(	SELECT
					member_ID
				,	first_DOS
				,	SUM( wasted_units )										AS	count_of_wasted_units
				,	SUM( administered_units )								AS	count_of_administered_units
				,	count_of_wasted_units + count_of_administered_units
																			AS	TOTAL_UNITS
				,	SUM( paid_for_wasted )									AS	paid_for_wasted_units
				,	SUM( paid_for_administered )							AS	paid_for_administered_units
				,	paid_for_wasted_units + paid_for_administered_units
																			AS	TOTAL_PAID
				,	SUM( allowed_amount )									AS	total_allowed_amount
				,	MIN( disposition_of_modifier )							AS	min_dom
				,	MAX( disposition_of_modifier )							AS	max_dom	
				,	COUNT( first_DOS ) OVER ( PARTITION BY member_ID )		AS	total_dosage_count
				,	FIRST_VALUE( first_DOS )
						OVER ( PARTITION BY member_ID ORDER BY first_DOS
								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																			AS	loading_dose_date
				,	FIRST_VALUE( count_of_administered_units )
						OVER ( PARTITION BY member_ID ORDER BY first_DOS
								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
																			AS	loading_dose
				,	LAST_VALUE( count_of_administered_units ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
								ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																			AS	prev_dose
				,	LAST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
								ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING )
																			AS	prev_dose_date
				,	DATEDIFF( DAY, prev_dose_date, first_DOS )				AS	days_since_prev_dose
				,	FIRST_VALUE( first_DOS ) OVER ( PARTITION BY member_ID ORDER BY first_DOS
								ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING )
																			AS	next_dose_date
				,	DATEDIFF( DAY, first_DOS, next_dose_date )				AS	days_till_next_dose
				,	DATEDIFF( DAY, loading_dose_date, first_DOS ) = days_since_prev_dose
																			AS	first_dose_after_loading
				,	( prev_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
																			AS	prev_ratio
				,	( count_of_administered_units::FLOAT / days_till_next_dose::FLOAT )::FLOAT
																			AS	subs_ratio
				,	CASE	count_of_administered_units
						WHEN	0	THEN	1
						ELSE				( prev_ratio::FLOAT / subs_ratio::FLOAT )::FLOAT
					END														AS	test_ratio
				,	CASE	( prev_dose = 0 )
						WHEN	TRUE	THEN	1.0
						ELSE					( count_of_administered_units::FLOAT / prev_dose::FLOAT )::FLOAT
					END														AS	dosage_change_factor
				,	CASE	( days_since_prev_dose = 0 )
						WHEN	TRUE	THEN	1.0
						ELSE					( days_till_next_dose::FLOAT / days_since_prev_dose::FLOAT )::FLOAT
					END														AS	administration_gap_factor
				,	CASE	(		count_of_administered_units > 95
								AND	date_in_time_window					)
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_A	--	single dose of more than 95 units in time window	#2
				,	CASE	(		count_of_administered_units IN ( 44, 88 )
								AND	date_in_time_window							)
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_B	--	single dose of 44 or 88 units in time window	#3
				,	CASE	(		count_of_administered_units = 0
								AND	date_in_time_window					)
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_C	--	zero units administered in time window		#20
				,	CASE	date_in_time_window
						WHEN	TRUE	THEN	MAX( abnormality_pre_flag_D )
						ELSE					'0'
					END														AS	abnormality_flag_D	--	units less than 5.0 not labelled waste (JW) in time window	#7
				,	CASE	(		count_of_administered_units IN ( 15, 30, 45, 60, 75, 90 )
								AND	date_in_time_window											)
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_E	--	units a multiple of 15 in time window	#6
				,	CASE		date_in_time_window
							AND	NOT	first_dose_after_loading
							AND	count_of_administered_units		>	0
							AND	prev_dose						>	0
							AND	(		test_ratio				>=	1.5
									OR	test_ratio				<=	0.666666667	)
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_F	--	sudden break in units per day during time window	#4
				,	CASE		date_in_time_window
							AND	dosage_change_factor		>=	1.5
							AND	administration_gap_factor	>=	0.9
							AND	administration_gap_factor	<=	1.1
						WHEN	TRUE	THEN	'1'
						ELSE					'0'
					END														AS	abnormality_flag_G	--	doubled units without doubled time gap (roughly), during time window	#1
			FROM
					(	SELECT
								claims.ClaimNumber			AS	claim_ID
							,	claims.MemberID				AS	member_ID
							,	claims.LineNumber			AS	line_num
							,	CASE	claims.ClaimStatus
									WHEN	'D'	THEN	'unpaid'
									WHEN	'F'	THEN	'paid'
								END							AS	claim_payment_status
							,	CASE	claims.CPTCode1
									WHEN	'J9355'	THEN	'herceptin'
									ELSE					NULL
								END							AS	administered
							,	claims.ProcedureCodeModifier1
							,	CASE	claims.ProcedureCodeModifier1	IS	NULL
									WHEN	TRUE	THEN	'pcm_IS_null'
									ELSE					'pcm_NOT_null'
								END							AS	disposition_of_modifier
							,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
											AND	claims.ProcedureCodeModifier1	=	'JW'			)
									WHEN	TRUE	THEN	claims.Units::FLOAT
									WHEN	FALSE	THEN	0.0
								END							AS	wasted_units
							,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
											OR	(		disposition_of_modifier			=	'pcm_NOT_null'
													AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
									WHEN	TRUE	THEN	claims.Units::FLOAT
									WHEN	FALSE	THEN	0.0
								END							AS	administered_units
							,	CASE	(		disposition_of_modifier			=	'pcm_NOT_null'
											AND	claims.ProcedureCodeModifier1	=	'JW'			)
									WHEN	TRUE	THEN	claims.ClaimPaidAmount
									WHEN	FALSE	THEN	0.0
								END							AS	paid_for_wasted
							,	CASE	(		(		disposition_of_modifier			=	'pcm_IS_null'		)
											OR	(		disposition_of_modifier			=	'pcm_NOT_null'
													AND	claims.ProcedureCodeModifier1	!=	'JW'			)	)
									WHEN	TRUE	THEN	claims.ClaimPaidAmount
									WHEN	FALSE	THEN	0.0
								END							AS	paid_for_administered
							,	claims.Units				AS	units
							,	claims.ClaimPaidAmount		AS	paid_amount
							,	claims.ClaimAllowedAmount	AS	allowed_amount
							,	claims.FirstDOS				AS	first_DOS
							,	CASE		(		units::float			<	5.0		)
										AND	(		ProcedureCodeModifier1	!=	'JW'
												OR	ProcedureCodeModifier1	IS	NULL	)
									WHEN	TRUE	THEN	'1'
									WHEN	FALSE	THEN	'0'
								END							AS	abnormality_pre_flag_D
							,	( DATEDIFF( DAY, '2017-05-01', first_DOS )	>=	0 )
															AS	date_in_time_window
					FROM
								ESRD_clean_raw.medical_claims							claims
						JOIN	(	SELECT DISTINCT	member_ID
									FROM			whaight.HFNY_herc_claims_clean	)	herc
						ON		claims.MemberID	=	herc.member_ID
					WHERE
							claim_payment_status	=	'paid'
						AND	administered			=	'herceptin'
						AND	paid_amount				>	0
				)	baseTable
			GROUP BY
					member_ID
				,	first_DOS
				,	date_in_time_window
		)								baseTable
	LEFT JOIN
		ESRD_clean_raw.medical_claims	crmc
	ON
			crmc.MemberID	=	baseTable.member_ID
		AND	crmc.FirstDOS	=	baseTable.first_DOS
WHERE
		baseTable.abnormality_flag_A	=	'1'
	OR	baseTable.abnormality_flag_B	=	'1'
	OR	baseTable.abnormality_flag_C	=	'1'
	OR	baseTable.abnormality_flag_D	=	'1'
	OR	baseTable.abnormality_flag_E	=	'1'
	OR	baseTable.abnormality_flag_F	=	'1'
	OR	baseTable.abnormality_flag_G	=	'1'
ORDER BY
		baseTable.member_ID	ASC
	,	baseTable.first_DOS	ASC
;