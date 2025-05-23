"use client"

import * as React from "react"
import { CalendarIcon } from "lucide-react"
import { format } from "date-fns"

import { cn } from "lpg-ui/lib/utils"
import { Button } from "lpg-ui/components/ui/button" // Assuming Button is in the same directory structure
import { Calendar } from "lpg-ui/components/ui/calendar" // Assuming Calendar will be created
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "lpg-ui/components/ui/popover" // Assuming Popover will be created

export function DatePicker() {
  const [date, setDate] = React.useState<Date>()

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant={"outline"}
          className={cn(
            "w-[280px] justify-start text-left font-normal",
            !date && "text-muted-foreground"
          )}
        >
          <CalendarIcon className="mr-2 h-4 w-4" />
          {date ? format(date, "PPP") : <span>Pick a date</span>}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto p-0">
        <Calendar
          mode="single"
          selected={date}
          onSelect={setDate}
          initialFocus
        />
      </PopoverContent>
    </Popover>
  )
}
