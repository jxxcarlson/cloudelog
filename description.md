# Cloudelog.app

Cloudelog.app managages logs.  

# Data mdel 

## Log

A log has

- id
- name
- creation data
- modification date
- description
- list of entries

An entry has

- id 
- quantity: Float
- units: Minutes | Hours | Kilometers | Miles | Custom String                                                                                                                                    
- date-time (creation date)
- description/comment

## User

A user has

- email
- password
- creation data
- modification date
- list of logs
- current log (id)


# User inteface

## Sign in Sign up page

## List of logs page

- New log button, with fields for the log name and the units
- Edit and delete buttons
- List of logs

Clicking on an item in the list of logs opens the log.
That log becomes the current log

## Log page

- Displays the current log as a scrolling list of items.
- The header of the log page is the log name,
  the total number of days in the log, the total of the log quantities,
  and the average quantity per day, and a button and quantity field 
  for for a new log item.  
  Below these, the description/comment
- Date of a log is created automatically. User enters quantity and description.
  User can edit or delete an item using per/item controls
- Below the header is the list of items:
- Item: date, quantity; below that description/comment

## Tech stack

Postgres, Hasql, Elm 

Example: /Users/carlson/dev/greppit




