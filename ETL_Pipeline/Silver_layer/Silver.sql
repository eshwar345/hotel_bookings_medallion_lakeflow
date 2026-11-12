CREATE OR REFRESH MATERIALIZED VIEW silver_bookings_clean (
  CONSTRAINT valid_stay_dates EXPECT (check_out_date > check_in_date) ON VIOLATION DROP ROW,
  CONSTRAINT valid_room_rate  EXPECT (room_rate >= 0) ON VIOLATION DROP ROW
) AS
SELECT DISTINCT
  booking_id,
  guest_id,
  booking_date,
  check_in_date,
  check_out_date,
  COALESCE(nights, DATEDIFF(check_out_date, check_in_date)) AS nights,
  TRIM(hotel_name) AS hotel_name,
  COALESCE(INITCAP(TRIM(city)), 'Unknown') AS city,
  INITCAP(TRIM(region)) AS region,
  INITCAP(TRIM(room_type)) AS room_type,
  COALESCE(INITCAP(TRIM(booking_channel)), 'Unknown') AS booking_channel,
  guests,
  room_rate,
  COALESCE(total_amount, DATEDIFF(check_out_date, check_in_date) * room_rate) AS total_amount,
  COALESCE(discount_amount, 0) AS discount_amount,
  INITCAP(TRIM(meal_plan)) AS meal_plan,
  TRIM(payment_method) AS payment_method,
  INITCAP(TRIM(payment_status)) AS payment_status,
  INITCAP(TRIM(booking_status)) AS booking_status,
  guest_rating
FROM bronze_hotel_bookings;

CREATE OR REFRESH MATERIALIZED VIEW silver_bookings_rejected AS
SELECT DISTINCT
  *,
  CASE
    WHEN check_out_date <= check_in_date AND room_rate < 0 THEN 'Check-out not after check-in and negative room rate'
    WHEN check_out_date <= check_in_date THEN 'Check-out is not after check-in'
    ELSE 'Room rate is negative'
  END AS reject_reason
FROM bronze_hotel_bookings
WHERE check_out_date <= check_in_date OR room_rate < 0;