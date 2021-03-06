% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/transformations.R
\name{inout}
\alias{inout}
\title{Summarize trips when RFID loggers define in/out}
\usage{
inout(r, dir_in, type = "out", all = FALSE, pass = TRUE)
}
\arguments{
\item{r}{Data frame. Raw data frame.}

\item{dir_in}{Character vector. A vector in the format of 'id1_id2' where id1
is the outer RFID logger and id2 is the inner RFID logger for specifying
direction 'enter' as id1 to id2.}

\item{type}{Character. Either 'out' or 'in' depending on whether to
concentrate on time spent out or time spent in.}

\item{all}{Logical. Include all individuals even those that did not complete
any trips.}

\item{pass}{Logical. Pass 'extra' columns through the function and append
them to the output.}
}
\description{
When RFID loggers are set up in sequence to capture movements in or out of an
area (nest box, hive, etc.). This function assumes that if an individual
enters by A -> B then it must exit B -> A.
}
\details{
Specify \code{type} to indicate what the trip of interest is (either time
out, or time in, the area of interest). Assume loggers A follwed by B
indicates an exit. A full "out" trip must have an exit followed eventually by
an entry. The trip starts the moment an individual finishes exiting (ie.
arrives at B if the last read was at A) and ends the moment an individual
starts to enter (ie. arrives at A if the next read is at B). A full "in" trip
must have an entry follwed eventually by an exit. The trip starts the moment
an individual finishes entering (ie. arrives at A if the last read was at B)
and ends the moment an individual starts to exit (ie. arrives at B if the
next read is at A).

\code{trip_length} indicates the total time between the start of a trip and
the end of a trip. Sometimes an individual may exit (or enter), but might not
leave the area around the outside (or inside) logger. The
\code{max_time_away} column indicates the maximum amount of time the
individual was not detected by a logger during the trip. Where the
trip_length is roughly equivalent to the max_time_away, the individual likely
left the immediate area. Where the max_time_away is very small, the
individual may have spent much of the time hovering around the the logger.

Note that duplicate enters or exits (i.e. two or more successive exits/enters) are
ignored. Only the final exit followed by an entry (or the final entry,
followed by an exit) is considered. This means that some trips may not be
detected. It is less likely that a detected trip represents more than one
trip, however, as both an exit and an entry would have had to be missed.
}
