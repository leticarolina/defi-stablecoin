export function UserStats({ statTitle, children }) {
    return (
        <div >
            <span className="text-gray-700 font-semibold">{statTitle}</span>{" "}
            <span className="text-gray-800">
                {children}
            </span>
        </div>
    )

}