FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /server .

FROM alpine:3.20
WORKDIR /app
COPY --from=build /server .
RUN mkdir uploads
EXPOSE 8080
CMD ["./server"]
