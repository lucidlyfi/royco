import csv
import sys

csv_file = sys.argv[1]
fill_amount = sys.argv[2]
time_since_auction_start = sys.argv[3]
now_minus_last_auction_start_time = sys.argv[4]
expected_incentive_amount = sys.argv[5]

with open(csv_file, 'a', newline='') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow([fill_amount, time_since_auction_start,
                    now_minus_last_auction_start_time, expected_incentive_amount])
